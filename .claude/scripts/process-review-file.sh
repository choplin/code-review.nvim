#!/bin/bash

# Process a single review file
# Usage: ./process-review-file.sh <filename>

if [ $# -ne 1 ]; then
  echo "Usage: $0 <filename>"
  exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
  echo "Error: File not found: $FILE"
  exit 1
fi

# Extract the ID from filename
BASENAME=$(basename "$FILE")
# Remove prefix and suffix using parameter expansion
ID="${BASENAME#action-required_}"
ID="${ID%.md}"

echo "Processing file: $FILE"
echo "ID: $ID"

# The actual processing will be done by Claude Code
# This script just handles the file renaming after processing

# Check if we should rename (this will be called after Claude adds the reply)
if [ -f "$FILE" ]; then
  # Replace prefix using parameter expansion
  NEW_FILE="${FILE/action-required_/waiting-review_}"
  echo "Renaming to: $NEW_FILE"
  mv "$FILE" "$NEW_FILE"
  echo "File renamed successfully"
else
  echo "File no longer exists (may have been already processed)"
fi
