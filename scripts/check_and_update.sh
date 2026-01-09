#!/bin/sh
set -eu

# Source common utilities
. "$(dirname "$0")/utils.sh"

CONFIG_FILE="/app/config/config.yml"
DATA_DIR="/app/data"
LAST_IP_FILE="$DATA_DIR/last_ip.txt"
LOCK_FILE="$DATA_DIR/ipupdate.lock"
NOTIFY_TS_DIR="$DATA_DIR/notify_ts"
mkdir -p "$DATA_DIR" "$NOTIFY_TS_DIR"

LABEL="${LABEL:-DDNS}"
MSMTP_ACCOUNT="${MSMTP_ACCOUNT:-default}"
RECIPIENTS_EMAILS="${RECIPIENTS_EMAILS:-}"
FORCE_NOTIFY="${FORCE_NOTIFY:-}"

for cmd in yq jq dig curl msmtp flock; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Command not found: $cmd"
  fi
done

cleanup() {
  rm -f "$LOCK_FILE"
}
trap cleanup EXIT INT TERM

if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    warn "Another instance is running. Exiting."
    exit 0
  fi
else
  if [ -f "$LOCK_FILE" ]; then
    warn "Another instance is running (lockfile present). Exiting."
    exit 0
  fi
  printf "%s" "$$" > "$LOCK_FILE"
fi



log "Retrieving current public IP"
current_ip=""
if retry_exec 5 1 'current_ip=$(curl -sS --max-time 10 api.ipify.org 2>/dev/null || printf ""); test -n "$current_ip"'; then
  current_ip=$(curl -sS --max-time 10 api.ipify.org 2>/dev/null || printf "")
else
  current_ip=$(curl -sS --max-time 10 ifconfig.co 2>/dev/null || printf "")
fi

if [ -z "$current_ip" ]; then
  err "Failed to retrieve the current IP address."
  exit 1
fi

touch "$LAST_IP_FILE"
last_ip=$(read_file_or_empty "$LAST_IP_FILE")
if [ "$current_ip" = "$last_ip" ]; then
  log "IP Address unchanged: $current_ip"
  exit 0
fi

log "IP changed: $last_ip -> $current_ip"
printf "%s\n" "$current_ip" > "$LAST_IP_FILE"

if [ ! -f "$CONFIG_FILE" ]; then
  warn "Config file not found: $CONFIG_FILE"
  exit 1
fi

total_actions=$(yq eval '.actions | length' "$CONFIG_FILE" -o=json | jq -r . 2>/dev/null || printf "0")
if [ -z "$total_actions" ] || [ "$total_actions" -lt 1 ]; then
  warn "No actions found in config.yml. Skipping."
fi

checklist=""
action_count=0
success_count=0
failure_count=0

append_check() {
  checklist="${checklist}$1\n"
}

# Collect domains explicitly specified per-action
domains_to_check=""
i=0
while [ "$i" -lt "$total_actions" ]; do
  # domain may be null or absent; yq prints "null" if absent in some versions
  domain=$(yq eval ".actions[$i].domain // \"\"" "$CONFIG_FILE" 2>/dev/null | sed 's/^"//;s/"$//')
  if [ -n "$domain" ] && [ "$domain" != "null" ]; then
    domains_to_check="${domains_to_check} ${domain}"
  fi
  i=$((i+1))
done

# Deduplicate domains list
if [ -n "$domains_to_check" ]; then
  domains_to_check=$(printf "%s" "$domains_to_check" | awk '{
    for(i=1;i<=NF;i++){ if(!seen[$i]++){ printf sep $i; sep=" " } }
  }')
fi

# Execute actions (per-action domain field is used only for DNS verification later)
i=0
while [ "$i" -lt "$total_actions" ]; do
  cmd_raw=$(yq eval ".actions[$i].command" "$CONFIG_FILE" 2>/dev/null | sed 's/^"//;s/"$//')
  desc=$(yq eval ".actions[$i].description" "$CONFIG_FILE" 2>/dev/null | sed 's/^"//;s/"$//')
  i=$((i+1))
  if [ -z "$cmd_raw" ] || [ -z "$desc" ]; then
    warn "Skipping malformed action #$i"
    continue
  fi
  action_count=$((action_count+1))

  escaped_ip=$(printf "%s" "$current_ip" | sed 's/[\/&]/\\&/g')
  cmd=$(printf "%s" "$cmd_raw" | sed "s/\\\$UPDATED_IP/$escaped_ip/g")

  log "Executing action: $desc"
  if retry_exec 3 1 "$cmd"; then
    append_check "✓ $desc — OK — exit=0"
    success_count=$((success_count+1))
  else
    append_check "✗ $desc — FAILED — exit!=0 after retries"
    failure_count=$((failure_count+1))
  fi
done

# Prepare checklist for notification
overall_status="SUCCESS"
if [ "$failure_count" -gt 0 ] && [ "$success_count" -gt 0 ]; then
  overall_status="PARTIAL"
elif [ "$failure_count" -gt 0 ] && [ "$success_count" -eq 0 ]; then
  overall_status="FAILURE"
fi

checklist_md=$(printf "%b" "$checklist")

# Add action results to checklist
action_summary="
---
**Action Execution Summary**
actions: $action_count (ok:$success_count fail:$failure_count)
"
checklist_md="${action_summary}${checklist_md}"

# Send initial notification with action results
sh /app/scripts/notify.sh \
  --config "$CONFIG_FILE" \
  --label "$LABEL" \
  --ip "$current_ip" \
  --status "$overall_status" \
  --checklist "$checklist_md" \
  --msmtp-account "$MSMTP_ACCOUNT" || warn "Failed to send initial update notification."

# Trigger background DNS verification if domains are configured
if [ -n "$domains_to_check" ]; then
  log "Triggering background DNS propagation verification..."
  sh /app/scripts/verify_dns_propagation.sh \
    --config "$CONFIG_FILE" \
    --ip "$current_ip" \
    --domains "$domains_to_check" \
    >/dev/null 2>&1 &
  # Note: Process runs in background; intentional fire-and-forget
fi

log "Finished update run: $overall_status"
if [ "$overall_status" = "FAILURE" ]; then
  exit 2
fi
exit 0
