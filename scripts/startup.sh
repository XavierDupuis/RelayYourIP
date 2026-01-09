# Source common utilities
. "$(dirname "$0")/utils.sh"

log "Setting up msmtp"
envsubst < msmtprc.template > /etc/msmtprc

log "Verifying configuration file config.yml"
if [ -f /app/config/config.yml ]; then
    log "Found $(yq eval '.actions | length' /app/config/config.yml -o=json | jq -r .) actions"
else
    touch /app/config/config.yml
    warn "config.yml file not found or empty. Created an empty config.yml."
fi

log "Setting up cron job with schedule '$CRON_SCHEDULE'"
echo "$CRON_SCHEDULE /app/scripts/check_and_update.sh > /proc/1/fd/1 2>&1" > /etc/crontabs/root

log "Starting cron daemon"
crond -l 2 -f