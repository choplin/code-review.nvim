#!/bin/bash

# Review Loop Monitor Script
# This script continuously monitors for action-required files and reports their status

REVIEW_DIR=".code-review"
CHECK_INTERVAL=5
STATUS_INTERVAL=30
last_status_time=$(date +%s)

echo "Starting review loop monitor..."
echo "Checking for action-required files every ${CHECK_INTERVAL} seconds"
echo "Status updates every ${STATUS_INTERVAL} seconds"
echo "---"

while true; do
  current_time=$(date +%s)

  # Find action-required files
  files=$(find "$REVIEW_DIR" -name "action-required_*.md" -type f 2>/dev/null)
  # Use grep -c for counting non-empty lines
  file_count=$(echo "$files" | grep -c -v '^$' || echo "0")

  if [ -n "$files" ] && [ "$files" != "" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found $file_count action-required file(s):"
    echo "$files" | while read -r file; do
      [ -n "$file" ] && echo "  - $file"
    done
    echo "ACTION_REQUIRED_FOUND"
    exit 0
  fi

  # Periodic status update
  time_diff=$((current_time - last_status_time))
  if [ $time_diff -ge $STATUS_INTERVAL ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No action-required files found. Continuing to monitor..."
    last_status_time=$current_time
  fi

  sleep $CHECK_INTERVAL
done
