echo "⚡  Setting up msmtp"
envsubst < msmtprc.template > /etc/msmtprc

echo "⚡  Verifying configuration file config.yml"
if [ -f /app/config.yml ]; then
    echo "🟢  Found $(yq eval '.actions | length' /app/config.yml -o=json | jq -r .) actions"
else
    touch /app/config.yml
    echo "🟠  config.yml file not found or empty. Created an empty config.yml."
fi

echo "⚡  Setting up cron job with schedule '$CRON_SCHEDULE'"
echo "$CRON_SCHEDULE /app/check_and_update.sh > /proc/1/fd/1 2>&1" > /etc/crontabs/root

echo "⚡  Starting cron daemon"
crond -l 2 -f