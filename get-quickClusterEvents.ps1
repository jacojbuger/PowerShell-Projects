<#
Version: 2.1
Purpose : Display cluster failover/resource events from last 24 hours
Platform: Windows Server 2022 (Server Core friendly)

Changes:
- Handles missing Event IDs gracefully
- Reports IDs not seen in last 24 hours
- Prevents Get-WinEvent failures from unsupported IDs
- Displays latest 20 matching events
#>

$LogName   = "Microsoft-Windows-FailoverClustering/Operational"
$StartTime = (Get-Date).AddHours(-24)

$EventIDs = @(
    1069,1205,1135,1137,1558,1641,1652,1653,
    1129,1130,1136,1177,1228,1230,5120,5142,
    1254,1227,5152,5140,1296,1155,1573,1561,
    21502,21503,21509
)

try {
    Write-Host "Reading cluster events from last 24 hours..." -ForegroundColor Cyan

    $allEvents = Get-WinEvent -FilterHashtable @{
        LogName   = $LogName
        StartTime = $StartTime
    } -ErrorAction Stop
}
catch {
    Write-Host "Failed to read cluster event log: $($_.Exception.Message)" -ForegroundColor Red
    return
}

$events = $allEvents |
    Where-Object { $_.Id -in $EventIDs } |
    Sort-Object TimeCreated -Descending

if (-not $events) {
    Write-Host ""
    Write-Host "No matching cluster events found in the last 24 hours." -ForegroundColor Yellow
}
else {

    Write-Host ""
    Write-Host "=== Cluster Failover / Resource Events (Last 24 Hours) ==="
    Write-Host ""

    $events |
        Select-Object -First 20 |
        ForEach-Object {

            $resource = if ($_.Message -match "Resource '(.+?)'") {
                $matches[1]
            }
            else {
                "N/A"
            }

            $group = if ($_.Message -match "Cluster resource group '(.+?)'") {
                $matches[1]
            }
            else {
                "N/A"
            }

            Write-Host "Time      : $($_.TimeCreated)"
            Write-Host "Event ID  : $($_.Id)"
            Write-Host "Level     : $($_.LevelDisplayName)"
            Write-Host "Node      : $($_.MachineName)"
            Write-Host "Group     : $group"
            Write-Host "Resource  : $resource"
            Write-Host "Message   :"
            Write-Host $_.Message
            Write-Host ("-" * 70)
        }
}

# Report IDs not seen
$FoundIDs   = $events.Id | Sort-Object -Unique
$MissingIDs = $EventIDs | Where-Object { $_ -notin $FoundIDs }

Write-Host ""
Write-Host "=== Event ID Summary ===" -ForegroundColor Cyan
Write-Host ""

foreach ($Id in $EventIDs) {

    $Count = ($events | Where-Object Id -eq $Id).Count

    if ($Count -gt 0) {
        Write-Host ("ID {0,-6} : {1} occurrence(s)" -f $Id, $Count) -ForegroundColor Green
    }
    else {
        Write-Host ("ID {0,-6} : skipped (not present in last 24 hours)" -f $Id) -ForegroundColor DarkYellow
    }
}
