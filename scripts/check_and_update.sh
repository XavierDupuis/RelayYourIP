#!/bin/sh
set -eu

print() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$1"; }
log()   { print "🔵 $1"; }
warn()  { print "🟠 $1"; }
err()   { print "⛔ $1"; }

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

now_epoch() { date +%s; }
read_file_or_empty() { [ -f "$1" ] && cat "$1" || printf ""; }

retry_exec() {
  max=${1:-5}; shift || true
  base_delay=${1:-1}; shift || true
  cmd_str=$1; shift || true
  n=0
  delay=$base_delay
  while :; do
    if sh -c "$cmd_str"; then
      return 0
    fi
    n=$((n+1))
    if [ "$n" -ge "$max" ]; then
      return 1
    fi
    sleep "$delay"
    delay=$((delay*2))
  done
}

curl_body_and_code() {
  url="$1"
  HTTP_CODE=""
  resp=$(curl -sS -w "\n%{http_code}" --max-time 10 "$url") || true
  HTTP_CODE=$(printf "%s" "$resp" | awk 'END{print}')
  printf "%s" "$(printf "%s" "$resp" | sed '$d')"
}

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

# DNS verification: use explicit domains_to_check
resolvers="1.1.1.1 8.8.8.8 9.9.9.9"
dns_ok_count=0
dns_total=0

for domain in $domains_to_check; do
  dns_total=$((dns_total+1))
  domain_ok=0
  for r in $resolvers; do
    out=$(dig +short @"$r" "$domain" A 2>/dev/null || printf "")
    out_one=$(printf "%s" "$out" | awk 'NR==1{print}')
    if [ "$out_one" = "$current_ip" ]; then
      append_check "✓ DNS @$r for $domain -> $out_one"
      domain_ok=1
      dns_ok_count=$((dns_ok_count+1))
      break
    else
      if [ -z "$out_one" ]; then
        append_check "✗ DNS @$r for $domain -> (no answer)"
      else
        append_check "✗ DNS @$r for $domain -> $out_one"
      fi
    fi
  done
  if [ "$domain_ok" -eq 0 ]; then
    append_check "✗ DNS verification failed for $domain"
  fi
done

overall_status="SUCCESS"
if [ "$failure_count" -gt 0 ] && [ "$success_count" -gt 0 ]; then
  overall_status="PARTIAL"
elif [ "$failure_count" -gt 0 ] && [ "$success_count" -eq 0 ]; then
  overall_status="FAILURE"
fi

# Notifications (rate-limiting removed)
title="[$LABEL] DDNS update — $overall_status"
summary="IP: $current_ip
Status: $overall_status
actions: $action_count (ok:$success_count fail:$failure_count)
DNS checks: $dns_ok_count / $dns_total
Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
"
checklist_md=$(printf "%b" "$checklist")

discord_url=$(yq eval '.alerting.discord.webhook_url // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
discord_mention=$(yq eval '.alerting.discord.mention // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
if [ -n "$discord_url" ] && [ "$discord_url" != "null" ]; then
  case "$overall_status" in
    SUCCESS) color=65280 ;;
    PARTIAL) color=16753920 ;;
    FAILURE) color=16711680 ;;
    *) color=0 ;;
  esac
  max_len=1900
  cb=$(printf "%s\n\n%s" "$summary" "$checklist_md")
  if [ "$(printf "%s" "$cb" | wc -c | tr -d ' ')" -gt "$max_len" ]; then
    cb="$(printf "%s" "$cb" | awk -v L=$max_len '{s=substr($0,1,L); print s"...[truncated]"}')"
  fi
  payload=$(jq -n --arg content "$discord_mention" --arg title "$title" --arg body "$cb" --argjson color "$color" \
    '{content:$content, embeds:[{title:$title, description:$body, color:$color}] }')
  if curl -sS -H "Content-Type: application/json" -X POST -d "$payload" "$discord_url" >/dev/null 2>&1; then
    log "Discord notification sent."
  else
    warn "Discord notification failed."
  fi
fi

webhook_url=$(yq eval '.alerting.webhook.url // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
webhook_token=$(yq eval '.alerting.webhook.bearer_token // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
if [ -n "$webhook_url" ] && [ "$webhook_url" != "null" ]; then
  json=$(jq -n --arg label "$LABEL" --arg ip "$current_ip" --arg status "$overall_status" --arg checklist "$checklist_md" \
    '{label:$label, ip:$ip, status:$status, checklist:$checklist}')
  hdrs="-H Content-Type: application/json"
  if [ -n "$webhook_token" ] && [ "$webhook_token" != "null" ]; then
    hdrs="$hdrs -H Authorization: Bearer $webhook_token"
  fi
  if eval "curl -sS $hdrs -X POST -d \"\$json\" \"$webhook_url\" >/dev/null 2>&1"; then
    log "Webhook notification sent."
  else
    warn "Webhook notification failed."
  fi
fi

email_recipients=$(yq eval '.alerting.email.recipients // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
email_from=$(yq eval '.alerting.email.from // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
if [ -n "$email_recipients" ] && [ "$email_recipients" != "null" ]; then
  subject="[$LABEL] DDNS update — $overall_status — $current_ip"
  body="$(printf "%s\n\nactions:\n%s\n" "$summary" "$checklist_md")"
  {
    printf "Subject: %s\n" "$subject"
    [ -n "$email_from" ] && printf "From: %s\n" "$email_from"
    printf "\n%s\n" "$body"
  } | msmtp -a "$MSMTP_ACCOUNT" "$email_recipients" >/dev/null 2>&1 && log "Email notification sent." || warn "Email notification failed."
fi

log "Finished update run: $overall_status"
if [ "$overall_status" = "FAILURE" ]; then
  exit 2
fi
exit 0
