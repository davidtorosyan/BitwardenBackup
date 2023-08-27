#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# TODO
# purge
# health checks
# versioning

# constants
$appRoot = Join-Path -Path $env:AppData -ChildPath "BitwardenBackup"
$appLogFile = Join-Path -Path $appRoot -ChildPath "logs\logs.txt"
$appBackups = Join-Path -Path $appRoot -ChildPath "backups"

function _main {
  Start-Transcript -Path $appLogFile -Append -UseMinimalHeader
  try {
    runBackup
    scheduleTask
  }
  finally {
    Stop-Transcript
  }
}


function runBackup {
  Write-Host 'Starting Bitwarden backup.'

  # https://bitwarden.com/help/data-storage/

  # Set your Healthchecks.io ping URL
  $pingUrl = "https://hc-ping.com/YOUR_PING_URL"

  # Set the source and destination paths
  $dataJson = "$env:AppData\Bitwarden\data.json"

  if (-not (Test-Path -Path $dataJson -PathType Leaf)) {
    # Invoke-RestMethod -Uri $pingUrl -Method Post -StatusCode 400 -Body "Source file not found."
    Write-Warning "Unable to find data.json file. Have you installed Bitwarden? https://bitwarden.com/download/"
    return
  }

  if (-not (Test-Path -Path $appBackups -PathType Container)) {
    New-Item -Path $appBackups -ItemType Directory | Out-Null
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
    return
  }

  # Generate a timestamp for the new filename
  $backupName = "data_$timestamp.json"

  # Combine the destination folder and filename
  $backupJson = Join-Path -Path $appBackups -ChildPath $backupName

  if (Test-Path -Path $backupJson -PathType Leaf) {
    Write-Warning "Backup file already exists, is sync running?: $backupJson"
    return
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
    return
  }
}

function scheduleTask {
  $taskName = "BitwardenBackupTask"
  $scheduledTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

  if ($scheduledTask) {
    Write-Host "Scheduled task already exists."
    return
  }
  
  $action = New-ScheduledTaskAction -Execute "cmd" -Argument "/c start /min `"`" pwsh -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $PSCommandPath"
  $trigger = New-ScheduledTaskTrigger -Daily -At 3am
  Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskName -Description "Task to backup Bitwarden data" | Out-Null
  Write-Host "Created new scheduled task."
}

_main