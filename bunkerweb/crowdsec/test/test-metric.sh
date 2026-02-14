#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../../.."

# ---------- helpers ----------
RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; BLU=$'\033[34m'; RST=$'\033[0m'
ok()   { echo "${GRN}✔${RST} $*"; }
warn() { echo "${YEL}⚠${RST} $*"; }
err()  { echo "${RED}✘${RST} $*"; }
info() { echo "${BLU}ℹ${RST} $*"; }

need() { command -v "$1" >/dev/null 2>&1 || { err "missing command: $1"; exit 2; }; }

need docker
need awk
need sed
need grep

# Use docker compose (v2) by default; allow override.
COMPOSE_BIN="${COMPOSE_BIN:-sudo docker compose}"

if ! $COMPOSE_BIN version >/dev/null 2>&1; then
  err "docker compose not available (v2). Set COMPOSE_BIN if needed."
  exit 2
fi

# ---------- locate crowdsec container ----------
CROWDSEC_CID="$($COMPOSE_BIN ps -q crowdsec 2>/dev/null || true)"
if [[ -z "${CROWDSEC_CID}" ]]; then
  err "cannot find crowdsec container id. Is the service name 'crowdsec' in compose?"
  $COMPOSE_BIN ps || true
  exit 3
fi

STATE="$(sudo docker inspect -f '{{.State.Status}}' "$CROWDSEC_CID" 2>/dev/null || true)"
if [[ "$STATE" != "running" ]]; then
  err "crowdsec container is not running (state=$STATE)"
  sudo docker ps -a --no-trunc | grep -F "$CROWDSEC_CID" || true
  exit 3
fi
ok "crowdsec container running: $CROWDSEC_CID"

# ---------- basic cscli availability ----------
if ! sudo docker exec "$CROWDSEC_CID" cscli version >/dev/null 2>&1; then
  err "cscli not working inside crowdsec container"
  sudo docker exec "$CROWDSEC_CID" sh -lc 'ls -la /usr/local/bin/cscli /usr/bin/cscli 2>/dev/null || true'
  exit 4
fi
ok "cscli available"

# ---------- collect metrics ----------
METRICS="$(sudo docker exec "$CROWDSEC_CID" sh -lc 'cscli metrics 2>/dev/null' || true)"
if [[ -z "$METRICS" ]]; then
  err "cscli metrics returned empty output"
  exit 4
fi

echo
info "Raw metrics (for reference):"
echo "$METRICS"
echo

# ---------- parse: Local API routes hits ----------
hb_hits="$(echo "$METRICS" | awk '
  $1=="/v1/heartbeat" && $2=="GET" {print $3}
' | tail -n 1)"
login_hits="$(echo "$METRICS" | awk '
  $1=="/v1/watchers/login" && $2=="POST" {print $3}
' | tail -n 1)"
usage_hits="$(echo "$METRICS" | awk '
  $1=="/v1/usage-metrics" && $2=="POST" {print $3}
' | tail -n 1)"

# Some tables can be missing => default 0
hb_hits="${hb_hits:-0}"
login_hits="${login_hits:-0}"
usage_hits="${usage_hits:-0}"

echo "== Local API sanity =="
echo "heartbeat hits : $hb_hits"
echo "login hits     : $login_hits"
echo "usage-metrics  : $usage_hits"
echo

# ---------- parse: Acquisition metrics totals ----------
# Sum of "Lines read/parsed/unparsed" from acquisition table (best-effort)
# We ignore header/separator lines; pick rows that start with something like docker:/...
acq_totals="$(echo "$METRICS" | awk '
  $1 ~ /^[a-z]+:\/\// {
    read += $2
    parsed += ($3=="-"?0:$3)
    unparsed += ($4=="-"?0:$4)
  }
  END { printf("%d %d %d\n", read, parsed, unparsed) }
')"
acq_read="$(echo "$acq_totals" | awk '{print $1}')"
acq_parsed="$(echo "$acq_totals" | awk '{print $2}')"
acq_unparsed="$(echo "$acq_totals" | awk '{print $3}')"

unparsed_ratio="N/A"
if [[ "$acq_read" -gt 0 ]]; then
  unparsed_ratio="$(awk -v u="$acq_unparsed" -v r="$acq_read" 'BEGIN{printf("%.1f", (u*100)/r)}')%"
fi

echo "== Acquisition totals =="
echo "lines read     : $acq_read"
echo "lines parsed   : $acq_parsed"
echo "lines unparsed : $acq_unparsed"
echo "unparsed ratio : $unparsed_ratio"
echo

# ---------- parse: Parser metrics (key parsers) ----------
# Extract stats for important parsers if present
bw_hits="$(echo "$METRICS" | awk '$1=="bunkerity/bunkerweb-logs"{print $2}' | tail -n 1)"
bw_parsed="$(echo "$METRICS" | awk '$1=="bunkerity/bunkerweb-logs"{print $3}' | tail -n 1)"
bw_unparsed="$(echo "$METRICS" | awk '$1=="bunkerity/bunkerweb-logs"{print $4}' | tail -n 1)"

http_hits="$(echo "$METRICS" | awk '$1=="crowdsecurity/http-logs"{print $2}' | tail -n 1)"
http_parsed="$(echo "$METRICS" | awk '$1=="crowdsecurity/http-logs"{print $3}' | tail -n 1)"
http_unparsed="$(echo "$METRICS" | awk '$1=="crowdsecurity/http-logs"{print $4}' | tail -n 1)"

echo "== Parser focus (best-effort) =="
[[ -n "${bw_hits:-}" ]]   && echo "bunkerity/bunkerweb-logs : hits=${bw_hits:-?} parsed=${bw_parsed:-?} unparsed=${bw_unparsed:-?}" || echo "bunkerity/bunkerweb-logs : (not found)"
[[ -n "${http_hits:-}" ]] && echo "crowdsecurity/http-logs  : hits=${http_hits:-?} parsed=${http_parsed:-?} unparsed=${http_unparsed:-?}" || echo "crowdsecurity/http-logs  : (not found)"
echo

# ---------- parse: Whitelist hits ----------
wl_private="$(echo "$METRICS" | awk '$1=="crowdsecurity/whitelists"{print $3}' | tail -n 1)"
wl_public_dns="$(echo "$METRICS" | awk '$1=="crowdsecurity/public-dns-allowlist"{print $3}' | tail -n 1)"
wl_private="${wl_private:-0}"
wl_public_dns="${wl_public_dns:-0}"

echo "== Whitelist hits =="
echo "private ranges whitelist hits : $wl_private"
echo "public DNS allowlist hits     : $wl_public_dns"
echo

# ---------- verdict ----------
# Heuristic:
# - Must have heartbeat > 0 (local API alive)
# - Should have acquisition parsed > 0 (ingesting something)
# - If parsed == 0 but read > 0 => likely log format mismatch / acquisition config wrong
# - If nearly everything is whitelisted, warn (could be expected in lab / private IP)
status=0

echo "== Verdict =="
if [[ "$hb_hits" -gt 0 ]]; then
  ok "Local API alive (heartbeat hits > 0)"
else
  err "Local API might be down (no /v1/heartbeat hits)"
  status=10
fi

if [[ "$acq_read" -gt 0 && "$acq_parsed" -gt 0 ]]; then
  ok "Acquisition is parsing logs (parsed > 0)"
elif [[ "$acq_read" -gt 0 && "$acq_parsed" -eq 0 ]]; then
  err "Acquisition reads logs but parses 0 lines → likely wrong parser / log format / acquisition config"
  status=11
else
  warn "No acquisition lines read; may be idle or acquisition not configured"
  status=$(( status==0 ? 12 : status ))
fi

if [[ "$acq_read" -gt 0 ]]; then
  # If >70% unparsed, call it out (tune threshold as you like)
  unp="$(awk -v u="$acq_unparsed" -v r="$acq_read" 'BEGIN{ if(r==0)print 0; else print (u*100)/r }')"
  if awk -v x="$unp" 'BEGIN{exit !(x>70)}'; then
    warn "High unparsed ratio (${unparsed_ratio}) → likely mixed sources or partial parser mismatch"
  fi
fi

if [[ "$wl_private" -gt 0 ]]; then
  warn "Private-range whitelist hits detected ($wl_private). If you're testing from 192.168.x.x, this can hide real detections."
fi

# Show a quick next-step hint if something looks wrong
if [[ "$status" -ne 0 ]]; then
  echo
  info "Next checks you can run:"
  echo "  - docker logs $CROWDSEC_CID --tail=200"
  echo "  - docker exec $CROWDSEC_CID cscli collections list -a"
  echo "  - docker exec $CROWDSEC_CID cscli hub list"
  echo "  - docker exec $CROWDSEC_CID cscli decisions list"
  echo "  - docker exec $CROWDSEC_CID cscli explain --log <paste_one_access_log_line_here>"
fi

exit "$status"
