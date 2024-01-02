#!/bin/sh

print() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $1"
}

log() {
    print "⚡ $1"
}

warn() {
    print "🟠 $1"
}

current_ip=$(wget -qO- https://api.ipify.org)
# dig -4 +short myip.opendns.com @resolver1.opendns.com

last_ip_file="/app/data/last_ip.txt"

touch $last_ip_file
last_ip=$(cat $last_ip_file)

if [ "$current_ip" == "$last_ip" ]; then
    log "IP Address has not changed '$last_ip'"
    exit 0
fi

log "IP Address changed from '$last_ip' to '$current_ip'"
echo $current_ip > $last_ip_file

log "Sending email notification to $RECIPIENTS_EMAILS"
subject="[$LABEL] IP Address Change Notification"
body="\n$(date)\n\n$current_ip\n\n$LABEL"
echo -e "Subject: $subject\n$body" | msmtp -a $MSMTP_ACCOUNT $RECIPIENTS_EMAILS

config_file="/app/config/config.yml"
total_actions=$(yq eval '.actions | length' "$config_file" -o=json | jq -r .)

if [ "$total_actions" -lt 1 ]; then
    warn "No actions found in config.yml. Skipping."
    exit 0
fi

index=0
while [ "$index" -lt "$total_actions" ]; do

    command=$(yq eval '.actions['"$index"'].command' "$config_file")
    if [ -z "$command" ]; then
        warn "Action has missing command. Skipping."
        index=$((index + 1))
        continue
    fi

    description=$(yq eval '.actions['"$index"'].description' "$config_file")
    if [ -z "$description" ]; then
        warn "Action has missing description. Skipping."
        index=$((index + 1))
        continue
    fi

    # Replace new ip references with current ip
    command="${command/\$UPDATED_IP/$current_ip}"

    # Escape ampersands
    command="${command//&/\\&}"

    eval "$command"
    log "Executed '$description'"

    index=$((index + 1))
done