#!/bin/sh
# verify_dns_propagation.sh - Poll DNS resolvers until domains resolve to target IP or timeout
# Usage: verify_dns_propagation.sh --config <config.yml> --ip <ip> --domains <domain1,domain2,...> [--max-wait <seconds>] [--base-delay <seconds>]

set -eu

# Source common utilities
. "$(dirname "$0")/utils.sh"

CONFIG_FILE=""
TARGET_IP=""
DOMAINS_LIST=""
MAX_WAIT=600
BASE_DELAY=5
LABEL="${LABEL:-DDNS}"
MSMTP_ACCOUNT="${MSMTP_ACCOUNT:-default}"
RESOLVERS="1.1.1.1 8.8.8.8 9.9.9.9"

# Parse arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --ip)
      TARGET_IP="$2"
      shift 2
      ;;
    --domains)
      DOMAINS_LIST="$2"
      shift 2
      ;;
    --max-wait)
      MAX_WAIT="$2"
      shift 2
      ;;
    --base-delay)
      BASE_DELAY="$2"
      shift 2
      ;;
    *)
      err "Unknown argument: $1"
      exit 1
      ;;
  esac
done

# Validate required arguments
if [ -z "$CONFIG_FILE" ] || [ -z "$TARGET_IP" ] || [ -z "$DOMAINS_LIST" ]; then
  err "Usage: verify_dns_propagation.sh --config <config.yml> --ip <ip> --domains <domain1,domain2,...>"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  err "Config file not found: $CONFIG_FILE"
  exit 1
fi

# Convert comma-separated domains to space-separated
domains_to_check=$(printf "%s" "$DOMAINS_LIST" | tr ',' ' ')

# Deduplicate domains
if [ -n "$domains_to_check" ]; then
  domains_to_check=$(printf "%s" "$domains_to_check" | awk '{
    for(i=1;i<=NF;i++){ if(!seen[$i]++){ printf sep $i; sep=" " } }
  }')
fi

if [ -z "$domains_to_check" ]; then
  log "No domains to verify. Exiting."
  exit 0
fi

log "Starting DNS propagation verification for: $domains_to_check"
log "Target IP: $TARGET_IP"
log "Max wait: ${MAX_WAIT}s, Base delay: ${BASE_DELAY}s"

start_time=$(date +%s)
attempt=0
delay=$BASE_DELAY
all_propagated=0

while [ "$all_propagated" -eq 0 ]; do
  now=$(date +%s)
  elapsed=$((now - start_time))
  
  if [ "$elapsed" -gt "$MAX_WAIT" ]; then
    warn "DNS verification timeout exceeded (${MAX_WAIT}s). Giving up."
    break
  fi
  
  attempt=$((attempt+1))
  all_propagated=1
  checklist=""
  
  for domain in $domains_to_check; do
    domain_ok=0
    for r in $RESOLVERS; do
      out=$(dig +short @"$r" "$domain" A 2>/dev/null || printf "")
      out_one=$(printf "%s" "$out" | awk 'NR==1{print}')
      
      if [ "$out_one" = "$TARGET_IP" ]; then
        checklist="${checklist}✓ DNS @$r for $domain -> $out_one\n"
        domain_ok=1
        break
      else
        if [ -z "$out_one" ]; then
          checklist="${checklist}✗ DNS @$r for $domain -> (no answer)\n"
        else
          checklist="${checklist}✗ DNS @$r for $domain -> $out_one\n"
        fi
      fi
    done
    
    if [ "$domain_ok" -eq 0 ]; then
      all_propagated=0
      checklist="${checklist}✗ Domain $domain not yet propagated\n"
    fi
  done
  
  if [ "$all_propagated" -eq 1 ]; then
    log "All domains verified. DNS propagation complete."
    # Send success notification
    checklist_md=$(printf "%b" "$checklist")
    sh /app/scripts/notify.sh \
      --config "$CONFIG_FILE" \
      --label "$LABEL" \
      --ip "$TARGET_IP" \
      --status "DNS_VERIFIED" \
      --checklist "$checklist_md" \
      --msmtp-account "$MSMTP_ACCOUNT" || warn "Failed to send DNS verification notification."
    exit 0
  fi
  
  log "Attempt $attempt: Not all domains propagated yet. Elapsed: ${elapsed}s. Retrying in ${delay}s..."
  sleep "$delay"
  delay=$((delay * 2))
  if [ "$delay" -gt 120 ]; then
    delay=120
  fi
done

# Timeout reached
warn "DNS verification did not complete within ${MAX_WAIT}s."
checklist_md=$(printf "%b" "$checklist")
sh /app/scripts/notify.sh \
  --config "$CONFIG_FILE" \
  --label "$LABEL" \
  --ip "$TARGET_IP" \
  --status "DNS_TIMEOUT" \
  --checklist "$checklist_md" \
  --msmtp-account "$MSMTP_ACCOUNT" || warn "Failed to send DNS timeout notification."
exit 1
