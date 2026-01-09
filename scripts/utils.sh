#!/bin/sh
# utils.sh - Common utilities for RelayYourIP scripts
# This file contains shared functions for logging, file operations, and retries

# Logging functions with timestamps
print() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$1"; }
log()   { print "🔵 $1"; }
warn()  { print "🟠 $1"; }
err()   { print "⛔ $1"; }

# Utility to get current epoch timestamp
now_epoch() { date +%s; }

# Safe file reading - returns empty string if file doesn't exist
read_file_or_empty() { [ -f "$1" ] && cat "$1" || printf ""; }

# Retry execution with exponential backoff
# Usage: retry_exec [max_attempts] [base_delay_seconds] "command_string"
# Example: retry_exec 5 1 "curl -s https://api.example.com"
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

# Fetch HTTP response body and status code
# Usage: curl_body_and_code "https://example.com"
# Sets HTTP_CODE variable and outputs body to stdout
curl_body_and_code() {
  url="$1"
  HTTP_CODE=""
  resp=$(curl -sS -w "\n%{http_code}" --max-time 10 "$url") || true
  HTTP_CODE=$(printf "%s" "$resp" | awk 'END{print}')
  printf "%s" "$(printf "%s" "$resp" | sed '$d')"
}
