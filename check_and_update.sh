#!/bin/sh

current_ip=$(wget -qO- https://api.ipify.org)
# dig -4 +short myip.opendns.com @resolver1.opendns.com

touch /app/last_ip.txt
last_ip=$(cat /app/last_ip.txt)

if [ "$current_ip" != "$last_ip" ]; then
    echo "⚡  IP Address changed from '$last_ip' to '$current_ip'"
    echo "⚡  Sending email notification to $RECIPIENTS_EMAILS"
    subject="[$LABEL] IP Address Change Notification"
    body="\n$(date)\n\n$current_ip\n\n$LABEL"
    echo -e "Subject: $subject\n$body" | msmtp -a $MSMTP_ACCOUNT $RECIPIENTS_EMAILS
    echo $current_ip > /app/last_ip.txt
else
    echo "⚡  IP Address has not changed ('$last_ip')"
fi