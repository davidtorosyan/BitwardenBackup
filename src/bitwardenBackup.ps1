#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# https://bitwarden.com/help/data-storage/

# TODO
# purge
# health checks env
# versioning
# add links
# 6 hour fail check

# constants
$appRoot = Join-Path -Path $env:AppData -ChildPath "BitwardenBackup"
$appLogFile = Join-Path -Path $appRoot -ChildPath "logs\logs.txt"
$appBackups = Join-Path -Path $appRoot -ChildPath "backups"

function Start-Main {
  Start-Transcript -Path $appLogFile -Append -UseMinimalHeader
  try {
    Start-Backup
    New-Task
  }
  finally {
    Stop-Transcript
  }
}

# Set your Healthchecks.io ping URL
$pingUrl = "https://hc-ping.com/$pingKey/bitwarden-backup"

function Ping-Success {
  param([string]$Message)

  Invoke-RestMethod -Uri $pingUrl -Method Post -Body $Message | Out-Null
}

function Ping-Fail {
  param([string]$Message)

  Invoke-RestMethod -Uri $pingUrl/fail -Method Post -Body $Message | Out-Null
}


function Start-Backup {
  Write-Host 'Starting Bitwarden backup.'

  # Check source and destination
  $dataJson = "$env:AppData\Bitwarden\data.json"
  if (-not (Test-Path -Path $dataJson -PathType Leaf)) {
    Write-Warning "Unable to find data.json. Have you installed Bitwarden? https://bitwarden.com/download/"
    Ping-Fail "Unable to find data.json"
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
    Ping-Fail "Unable to find date string in data.json"
    return
  }

  # Check to see if the backup already exists
  $backupName = "data_$timestamp.json"
  $backupJson = Join-Path -Path $appBackups -ChildPath $backupName
  if (Test-Path -Path $backupJson -PathType Leaf) {
    # don't ping failure, since this could happen from just manually running too soon
    Write-Warning "Backup file already exists, is sync running?: $backupJson"
    return
  }

  # Copy the file to the destination
  try {
    Copy-Item -Path $dataJson -Destination $backupJson -ErrorAction Stop
    Write-Host "Successfully backed up file to $backupJson"
    Ping-Success "Backed up file to $backupJson"
  }
  catch {
    Write-Warning "Failed to copy file with error: $($_.Exception.Message)"
    Ping-Fail "Failed to copy file to backup location"
  }
}

function New-Task {
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

Start-Main