#!/bin/sh
# notify.sh - Unified notification dispatch for all channels
# Usage: notify.sh --config <config.yml> --label <label> --ip <ip> --status <status> --checklist <checklist> [--msmtp-account <account>]

set -eu

# Source common utilities
. "$(dirname "$0")/utils.sh"

CONFIG_FILE=""
LABEL="${LABEL:-DDNS}"
CURRENT_IP=""
OVERALL_STATUS=""
CHECKLIST=""
MSMTP_ACCOUNT="${MSMTP_ACCOUNT:-default}"

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --label)
      LABEL="$2"
      shift 2
      ;;
    --ip)
      CURRENT_IP="$2"
      shift 2
      ;;
    --status)
      OVERALL_STATUS="$2"
      shift 2
      ;;
    --checklist)
      CHECKLIST="$2"
      shift 2
      ;;
    --msmtp-account)
      MSMTP_ACCOUNT="$2"
      shift 2
      ;;
    *)
      err "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$CONFIG_FILE" ] || [ -z "$LABEL" ] || [ -z "$CURRENT_IP" ] || [ -z "$OVERALL_STATUS" ]; then
  err "Usage: notify.sh --config <config.yml> --label <label> --ip <ip> --status <status> --checklist <checklist>"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  err "Config file not found: $CONFIG_FILE"
  exit 1
fi

# Build summary
summary="IP: $CURRENT_IP
Status: $OVERALL_STATUS
Time: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

checklist_md="$CHECKLIST"

# Discord notification
discord_url=$(yq eval '.alerting.discord.webhook_url // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
discord_mention=$(yq eval '.alerting.discord.mention // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
if [ -n "$discord_url" ] && [ "$discord_url" != "null" ]; then
  case "$OVERALL_STATUS" in
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
  
  title="[$LABEL] DDNS update — $OVERALL_STATUS"
  payload=$(jq -n --arg content "$discord_mention" --arg title "$title" --arg body "$cb" --argjson color "$color" \
    '{content:$content, embeds:[{title:$title, description:$body, color:$color}] }')
  
  if curl -sS -H "Content-Type: application/json" -X POST -d "$payload" "$discord_url" >/dev/null 2>&1; then
    log "Discord notification sent."
  else
    warn "Discord notification failed."
  fi
fi

# Generic webhook notification
webhook_url=$(yq eval '.alerting.webhook.url // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
webhook_token=$(yq eval '.alerting.webhook.bearer_token // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
if [ -n "$webhook_url" ] && [ "$webhook_url" != "null" ]; then
  json=$(jq -n --arg label "$LABEL" --arg ip "$CURRENT_IP" --arg status "$OVERALL_STATUS" --arg checklist "$checklist_md" \
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

# Email notification
email_recipients=$(yq eval '.alerting.email.recipients // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
email_from=$(yq eval '.alerting.email.from // ""' "$CONFIG_FILE" 2>/dev/null || printf "")
if [ -n "$email_recipients" ] && [ "$email_recipients" != "null" ]; then
  subject="[$LABEL] DDNS update — $OVERALL_STATUS — $CURRENT_IP"
  body="$(printf "%s\n\n%s\n" "$summary" "$checklist_md")"
  {
    printf "Subject: %s\n" "$subject"
    [ -n "$email_from" ] && printf "From: %s\n" "$email_from"
    printf "\n%s\n" "$body"
  } | msmtp -a "$MSMTP_ACCOUNT" "$email_recipients" >/dev/null 2>&1 && log "Email notification sent." || warn "Email notification failed."
fi

log "Notifications completed."
