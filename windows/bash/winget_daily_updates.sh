#!/bin/bash

# Stop execution on any command failure, unset variable and return the exit code of pipelined commands 
set -euo pipefail

log_path="$LOCAL_LOG_PATH"
log_file="$log_path/winget_daily_updates_$(date "+%F").log"

# Create log directory if it doesn't exist
mkdir -p "$log_path"

# Remove the spinner/progress bar and add timestamp to each output line
function exec_cmd() {
  local tmp_out
  tmp_out=$(mktemp)

  # Run the command and capture output + exit code
  "$@" > "$tmp_out" 2>&1
  local exit_code=$?

  # If the output is empty and command succeeded, write a warning into the file
  if [[ ! -s "$tmp_out" && $exit_code -eq 0 ]]; then
    echo "[WARN] Command succeeded but produced no output" >> "$tmp_out"
  fi

  grep -vP '^\s+[\-\\|\/]+[\s]+$|▒▒' "$tmp_out" \
    | sed -E 's.[[:space:]]*[-\\\/\|]+[[:space:]]+..g' \
    | awk '{print strftime("[%Y-%m-%d %H:%M:%S]"), $0 }' \
    | tee -a "$log_file"

  rm -f "$tmp_out"
  return $exit_code
}

function print() {
  exec_cmd echo -e "$@"
}

function log_and_exec_cmd() {
  print "Executing: $*"
  exec_cmd "$@"
}

# Upgrade all apps, write logs to the console and log file. There would be atmost 1 log file for each day the script got executed.
log_and_exec_cmd winget upgrade -r --accept-package-agreements --accept-source-agreements --silent --disable-interactivity

print "Upgrade Completed."

# Purge logs older than 30 days
log_and_exec_cmd find "$log_path" -type f -name '*.log' -mtime +30 -exec rm -f {} +

print "Purged all available logs older than 30 days."

