#Requires -Version 7
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Run this script to backup your Bitwarden vault.
# Also creates a scheduled task.
# 
# For more info about how the data is stored, see:
# https://bitwarden.com/help/data-storage/
#
# For a way to decrypt the data, see:
# https://github.com/GurpreetKang/BitwardenDecrypt

# TODO
# fix healthchecks
# versioning

# constants
$appRoot = Join-Path -Path $env:AppData -ChildPath "BitwardenBackup"
$appLogFile = Join-Path -Path $appRoot -ChildPath "logs\logs.txt"
$appBackups = Join-Path -Path $appRoot -ChildPath "backups"

$hcDomain = "hc-ping.com"
$hcSlug = "bitwarden-backup"

$scheduledTaskName = "BitwardenBackupTask"
$scheduledTaskDescription = "Task to backup Bitwarden data"
$scheduledTaskTime = '3am'

$RetentionConfig = @{
  Daily   = 7
  Weekly  = 4
  Monthly = 6
  Yearly  = 1
}

$PruningPatterns = @{
  Daily   = "%Y-%m-%d"
  Weekly  = "%G-%V"
  Monthly = "%Y-%m"
  Yearly  = "%Y"
}

$extractDatePattern = "^data_(.*)$"

function Start-Main {
  Start-Transcript -Path $appLogFile -Append -UseMinimalHeader
  try {
    Set-PingKey
    Start-Backup
    Start-Prune
    New-Task
  }
  finally {
    Stop-Transcript
  }
}

function Get-PingUrl {
  "https://$hcDomain/$env:HC_PING_KEY/$hcSlug"
}

function Ping-Success {
  param([string]$Message)

  $pingUrl = Get-PingUrl
  Invoke-RestMethod -Uri $pingUrl -Method Post -Body $Message | Out-Null
}

function Ping-Fail {
  param([string]$Message)

  $pingUrl = Get-PingUrl
  Invoke-RestMethod -Uri $pingUrl/fail -Method Post -Body $Message | Out-Null
}

function Set-PingKey {
  if ($env:HC_PING_KEY) {
    Write-Host "Ping key already set."
    return
  }

  Write-Host "To continue, you need to create a HealthChecks account."
  Write-Host "Go to https://healthchecks.io/ and set up a check called '$hcSlug'."
  Write-Host "Then go to Settings > Ping key and hit Create."
  $pingKey = Read-Host -Prompt 'Input your HealthChecks ping key'
  if (!$pingKey) {
    Write-Warning "Need to set up a ping key to continue!"
    exit
  }

  $env:HC_PING_KEY = $pingKey
  [Environment]::SetEnvironmentVariable('HC_PING_KEY', $pingKey, 'User')
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

function Start-Prune {
  $jsonFiles = Get-ChildItem $appBackups

  $filenameToDateMap = @{}
  foreach ($file in $jsonFiles) {
    if ($file.Basename -match $extractDatePattern) {
      $dateString = $matches[1]
      $dateTime = [DateTime]::ParseExact($dateString, "yyyy-MM-ddTHH_mm_ss.fffZ", $null)
      $filenameToDateMap[$file.FullName] = $dateTime
    }
    else {
      Write-Warning "Unable to extract date from file: $file"
    }
  }
  
  $keep = Get-AllKeeps $filenameToDateMap
  $filenames = $filenameToDateMap.Keys
  $toDelete = @($filenames | Where-Object { $keep -notcontains $_ })

  if (-not $toDelete) {
    Write-Host "No files to prune. Total files: $($filenames.Count)"
    return
  }

  Write-Host "From $($filenames.Count) files, pruning $($toDelete.Count)"
  foreach ($filename in $toDelete) {
    Remove-Item -Path $filename -Force
  }
}

function Get-AllKeeps {
  param(
    [Hashtable]$filenameToDateMap
  )

  $sortedFiles = $filenameToDateMap.GetEnumerator() | Sort-Object { $_.Value } -Descending
  $keep = @()

  foreach ($rule in $PruningPatterns.Keys) {
    $pattern = $PruningPatterns[$rule]
    $num = $RetentionConfig[$rule]

    $keep += Get-Keeps $sortedFiles $pattern $num
  }

  return $keep | Sort-Object -unique
}

function Get-Keeps {
  param(
    [System.Object[]]$filenameToDateMap,
    [string]$pattern,
    [int]$num
  )

  $keep = @()

  $last = $null
  foreach ($fileEntry in $filenameToDateMap) {
    $filename = $fileEntry.Key
    $date = $fileEntry.Value

    $period = Get-Date $date -UFormat $pattern

    if ($period -ne $last) {
      $last = $period
      $keep += $filename
      if ($keep.Length -ge $num) {
        break
      }
    }
  }

  return $keep
}

function New-Task {
  $scheduledTask = Get-ScheduledTask -TaskName $scheduledTaskName -ErrorAction SilentlyContinue

  if ($scheduledTask) {
    Write-Host "Scheduled task already exists."
    return
  }
  
  # do this complicated incantation to have a very minimal window pop up
  # anything else requires admin permissions
  $action = New-ScheduledTaskAction -Execute "cmd" -Argument "/c start /min `"`" pwsh -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $PSCommandPath"
  $trigger = New-ScheduledTaskTrigger -Daily -At $scheduledTaskTime
  Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $scheduledTaskName -Description $scheduledTaskDescription | Out-Null
  Write-Host "Created new scheduled task called '$scheduledTaskName', set to run daily at $scheduledTaskTime."
  Write-Host "If you need to adjust it, do so in Task Scheduler."
}

Start-Main