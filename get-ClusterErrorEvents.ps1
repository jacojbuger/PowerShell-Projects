<#
Version: 3.0
Purpose : Pull last 20 failover/resource-related cluster events (24h)
Platform: Windows Server 2022 Core
#>

$LogName   = "Microsoft-Windows-FailoverClustering/Operational"
$StartTime = (Get-Date).AddHours(-24)

Write-Host "`nScanning cluster events from last 24 hours..."
Write-Host "--------------------------------------------------"

# Pull last 24 hours without ID restriction
$events = Get-WinEvent -FilterHashtable @{
    LogName   = $LogName
    StartTime = $StartTime
} -ErrorAction SilentlyContinue

if (-not $events) {
    Write-Host "No cluster events found in last 24 hours."
    return
}

# Filter for actual failover/resource activity
$filtered = $events | Where-Object {
    $_.LevelDisplayName -ne "Information" -or
    $_.Message -match 'fail|move|offline|online|arbitration|lost|ownership'
}

if (-not $filtered) {
    Write-Host "Cluster active but no failover/resource activity detected."
    return
}

$filtered |
Sort-Object TimeCreated -Descending |
Select-Object -First 20 |
Format-List TimeCreated, Id, LevelDisplayName, MachineName, Message
