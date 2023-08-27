#Requires -Version 5
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host 'Starting Bitwarden backup.'

# https://bitwarden.com/help/data-storage/

# Set your Healthchecks.io ping URL
$pingUrl = "https://hc-ping.com/YOUR_PING_URL"

# Set the source and destination paths
$dataJson = "$env:AppData\Bitwarden\data.json"
$backupDirectory = "$env:AppData\BitwardenBackup"

if (-not (Test-Path -Path $dataJson -PathType Leaf)) {
  # Invoke-RestMethod -Uri $pingUrl -Method Post -StatusCode 400 -Body "Source file not found."
  Write-Warning "Unable to find data.json file. Have you installed Bitwarden? https://bitwarden.com/download/"
  exit
}

if (-not (Test-Path -Path $backupDirectory -PathType Container)) {
  New-Item -Path $backupDirectory -ItemType Directory | Out-Null
}

# Get the sync timestamp
$data = Get-Content -Path $dataJson
$selectResults = $data | Select-String -Pattern '"lastSync": "(.*)"'
if ($selectResults) {
  $result = $selectResults[0].Matches.Groups[1].Value
  $timestamp = $result.Replace(":", "_")
}
else {
  Write-Warning "Date string not found in the file."
  exit
}


# Generate a timestamp for the new filename
$backupName = "data_$timestamp.json"

# Combine the destination folder and filename
$backupJson = Join-Path -Path $backupDirectory -ChildPath $backupName

if (Test-Path -Path $backupJson -PathType Leaf) {
  Write-Warning "Backup file already exists, is sync running?: $backupJson"
  exit
}

# Copy the file to the destination
try {
  Copy-Item -Path $dataJson -Destination $backupJson -ErrorAction Stop
  Write-Host "Successfully backed up file to $backupJson"
  # Invoke-RestMethod -Uri $pingUrl -Method Post -StatusCode 200 -Body "File copied to $backupJson"
}
catch {
  # Invoke-RestMethod -Uri $pingUrl -Method Post -StatusCode 500 -Body $errorMessage
  Write-Warning "Failed to copy file with error: $($_.Exception.Message)"
  exit;
}

# # Check if the scheduled task exists
# $taskName = "BitwardenBackupTask"
# $scheduledTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

# if (!$scheduledTask) {
#     # Create a new scheduled task
#     $trigger = New-ScheduledTaskTrigger -AtStartup
#     $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File 'C:\Path\To\Your\Script.ps1'"

#     Register-ScheduledTask -TaskName $taskName -Trigger $trigger -Action $action -User "Username" -Password "Password" -Description "Task to backup Bitwarden data"
#     Write-Host "Scheduled task created."
# } else {
#     Write-Host "Scheduled task already exists."
# }