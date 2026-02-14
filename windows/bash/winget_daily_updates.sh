#!/bin/bash

# Stop execution on any command failure, unset variable and return the exit code of pipelined commands 
set -xeuo pipefail

log_file_name="winget_daily_updates_$(date "+%F").log"
log_path="$LOCAL_LOG_PATH"
log_file="$log_path/$log_file_name"
log_file_windows_path="$LOCAL_WIN_LOG_PATH\\$log_file_name"

# Create log directory if it doesn't exist
mkdir -p "$log_path"

# Remove the spinner/progress bar and add timestamp to each output line
function exec_cmd() {
#  local tmp_out
#  tmp_out=$(mktemp)

  # Run the command and capture output + exit code
#  if "$@" > "$tmp_out" 2>&1; then
#    exit_code=0
#  else
#    exit_code=$?
#  fi

  # If the output is empty and command succeeded, write a warning into the file
#  if [[ ! -s "$tmp_out" && $exit_code -eq 0 ]]; then
#    echo "[WARN] Command succeeded but produced no output" >> "$tmp_out"
#  fi

#  grep -vP '^\s+[\-\\|\/]+[\s]+$|▒▒|\.\.\.\.\.\.\.\.\.\.' "$tmp_out" \
  "$@" | grep -vP '^\s+[\-\\|\/]+[\s]+$|▒▒|\.\.\.\.\.\.\.\.\.\.' \
    | sed -E 's.[[:space:]]*[-\\\/\|]+[[:space:]]+..g' \
    | awk '{print strftime("[%Y-%m-%d %H:%M:%S]"), $0 }' \
    | tee -a "$log_file"

#  rm -f "$tmp_out"
  return $?
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
find "$log_path" -type f -name '*.log' -mtime +30 -exec rm -f {} +

print "Purged all available logs older than 30 days."

if winget list --upgrade-available --include-pinned | grep -qE 'Microsoft\.Edge'; then
  print  "Microsoft Edge update is available. Manually upgrading to the latest version..."

  microsoft_edge_installer_url=$(winget.exe show --id "Microsoft.Edge" | grep 'Installer Url' | sed "s/[[:space:]]*Installer Url:[[:space:]]*//g")
  microsoft_edge_installer_file=$(echo $microsoft_edge_installer_url | awk -F '/' '{ print $NF }')
  log_and_exec_cmd wget -O "$log_path/$microsoft_edge_installer_file" $microsoft_edge_installer_url
  log_and_exec_cmd powershell.exe -Command "msiexec /i $LOCAL_WIN_LOG_PATH\\$microsoft_edge_installer_file"

  print "Microsoft Edge upgraded to the latest available version"
fi

if winget list --upgrade-available --include-pinned | grep -qE 'Git\.Git'; then
  print "Git update is available. Preparing scheduled upgrade..."

  task_name="GitAutoUpgrade"
  task_script_path="$LOCAL_WIN_LOG_PATH\\git_upgrade_task.ps1"

  # Check if task already exists
  if schtasks /Query /TN "$task_name" > /dev/null 2>&1; then
    print "Scheduled task '$task_name' already exists. Skipping creation."
  else
    print "Creating scheduled task to run Git upgrade in 10 minutes..."

    # Write the upgrade PowerShell script
    cat > "$task_script_path" <<EOF
Start-Sleep -Seconds 5
Start-Transcript -Path "$log_file_windows_path" -Append
winget upgrade --id Git.Git --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --include-pinned
Stop-Transcript
Unregister-ScheduledTask -TaskName '$task_name' -Confirm:\$false
EOF

    # Calculate time 10 minutes from now
    run_time=$(powershell.exe -NoProfile -Command "(Get-Date).AddMinutes(10).ToString('HH:mm')")

    # Register the task
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "
      \$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File \"$task_script_path\"'
      \$trigger = New-ScheduledTaskTrigger -Once -At \"$run_time\"
      Register-ScheduledTask -TaskName '$task_name' -Action \$action -Trigger \$trigger -RunLevel Highest -Force
    "

    print "Scheduled Git upgrade task '$task_name' at $run_time."
  fi

else
  print "Git is already up to date."
fi



