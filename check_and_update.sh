#!/bin/sh

current_ip=$(wget -qO- https://api.ipify.org)
# dig -4 +short myip.opendns.com @resolver1.opendns.com

touch /app/last_ip.txt
last_ip=$(cat /app/last_ip.txt)

if [ "$current_ip" == "$last_ip" ]; then
    echo "⚡  IP Address has not changed ('$last_ip')"
    exit 0
fi


echo "⚡  IP Address changed from '$last_ip' to '$current_ip'"
echo $current_ip > /app/last_ip.txt

echo "⚡  Sending email notification to $RECIPIENTS_EMAILS"
subject="[$LABEL] IP Address Change Notification"
body="\n$(date)\n\n$current_ip\n\n$LABEL"
echo -e "Subject: $subject\n$body" | msmtp -a $MSMTP_ACCOUNT $RECIPIENTS_EMAILS

yaml_file="/app/config.yml"
total_actions=$(yq eval '.actions | length' "$yaml_file" -o=json | jq -r .)

if [ "$total_actions" -lt 1 ]; then
    echo "🟠  Warning: No actions found in config.yml. Skipping."
    exit 0
fi

index=0
while [ "$index" -lt "$total_actions" ]; do

    command=$(yq eval '.actions['"$index"'].command' "$yaml_file")
    if [ -z "$command" ]; then
        echo "🟠  Warning: Action has missing command. Skipping."
        index=$((index + 1))
        continue
    fi

    description=$(yq eval '.actions['"$index"'].description' "$yaml_file")
    if [ -z "$description" ]; then
        echo "🟠  Warning: Action has missing description. Skipping."
        index=$((index + 1))
        continue
    fi

    # Replace new ip references with current ip
    command="${command/\$UPDATED_IP/$current_ip}"

    # Escape ampersands
    command="${command//&/\\&}"

    eval "$command"
    echo "🟢  Executed: '$description'"

    index=$((index + 1))
done