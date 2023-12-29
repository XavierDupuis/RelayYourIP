echo "⚡  Setting up msmtp"
envsubst < msmtprc.template > /etc/msmtprc
echo "⚡  Setting up cron job with schedule '$CRON_SCHEDULE'"
echo "$CRON_SCHEDULE /app/check_and_update.sh > /proc/1/fd/1 2>&1" > /etc/crontabs/root
echo "⚡  Starting cron daemon"
crond -l 2 -f