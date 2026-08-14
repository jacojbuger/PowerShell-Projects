# Get critical and error events from System log (last 7 days)
$days = 7
$startTime = (Get-Date).AddDays(-$days)

Write-Host "Searching for Critical and Error events in the last $days days..." -ForegroundColor Yellow
Write-Host ""

# Get events from System log - Errors and Warnings
$systemEvents = @()
try {
    $systemEvents = Get-EventLog -LogName System -EntryType Error, Warning -After $startTime -ErrorAction Stop
    Write-Host "Found $($systemEvents.Count) System log entries" -ForegroundColor Cyan
} catch {
    Write-Host "No System log entries found or error occurred" -ForegroundColor Yellow
}

# Get events from Application log (exclude Event ID 3299)
$appEvents = @()
try {
    $appEvents = Get-EventLog -LogName Application -EntryType Error -After $startTime -ErrorAction Stop | 
        Where-Object { $_.EventID -ne 3299 }
    Write-Host "Found $($appEvents.Count) Application log errors" -ForegroundColor Cyan
} catch {
    Write-Host "No Application log errors found or log doesn't exist" -ForegroundColor Yellow
}

# Get Hyper-V Admin logs
$hypervEvents = @()
try {
    $hypervAdminLogs = @(
        "Microsoft-Windows-Hyper-V-VMMS-Admin",
        "Microsoft-Windows-Hyper-V-Compute-Admin",
        "Microsoft-Windows-Hyper-V-Config-Admin",
        "Microsoft-Windows-Hyper-V-Worker-Admin",
        "Microsoft-Windows-Hyper-V-VmSwitch-Operational"
    )
    
    foreach ($logName in $hypervAdminLogs) {
        $events = Get-WinEvent -LogName $logName -FilterXPath "*[System[Level=1 or Level=2 or Level=3]]" -MaxEvents 1000 -ErrorAction SilentlyContinue | 
            Where-Object { $_.TimeCreated -gt $startTime }
        $hypervEvents += $events
    }
    Write-Host "Found $($hypervEvents.Count) Hyper-V events" -ForegroundColor Cyan
} catch {
    Write-Host "No Hyper-V events found" -ForegroundColor Yellow
}

# Get Failover Cluster events
$clusterEvents = @()
try {
    $clusterLogs = @(
        "Microsoft-Windows-FailoverClustering/Operational",
        "Microsoft-Windows-FailoverClustering/Diagnostic",
        "Microsoft-Windows-FailoverClustering-Manager/Admin"
    )
    
    foreach ($logName in $clusterLogs) {
        $events = Get-WinEvent -LogName $logName -FilterXPath "*[System[Level=1 or Level=2 or Level=3]]" -MaxEvents 1000 -ErrorAction SilentlyContinue | 
            Where-Object { $_.TimeCreated -gt $startTime }
        $clusterEvents += $events
    }
    Write-Host "Found $($clusterEvents.Count) Cluster events" -ForegroundColor Cyan
} catch {
    Write-Host "No Cluster events found" -ForegroundColor Yellow
}

Write-Host ""

# Display System Events (limit to 25)
if ($systemEvents) {
    Write-Host "=== SYSTEM LOG EVENTS ===" -ForegroundColor Red
    $systemEvents | Select-Object -First 25 | Format-Table -AutoSize -Property TimeGenerated, EventID, Source, EntryType, Message
    Write-Host "Showing 25 of $($systemEvents.Count) Total System Events" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "No system events found." -ForegroundColor Green
}

# Display Application Events (limit to 25)
if ($appEvents) {
    Write-Host "=== APPLICATION LOG ERRORS ===" -ForegroundColor Red
    $appEvents | Select-Object -First 25 | Format-Table -AutoSize -Property TimeGenerated, EventID, Source, EntryType, Message
    Write-Host "Showing 25 of $($appEvents.Count) Total Application Errors" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "No application errors found." -ForegroundColor Green
}

# Display Hyper-V Events (limit to 25)
if ($hypervEvents) {
    Write-Host "=== HYPER-V EVENTS ===" -ForegroundColor Magenta
    $hypervEvents | Select-Object -First 25 | Format-Table -AutoSize -Property TimeCreated, ID, ProviderName, LevelDisplayName, Message
    Write-Host "Showing 25 of $($hypervEvents.Count) Total Hyper-V Events" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "No Hyper-V events found." -ForegroundColor Green
}

# Display Failover Cluster Events (limit to 25)
if ($clusterEvents) {
    Write-Host "=== FAILOVER CLUSTER EVENTS ===" -ForegroundColor DarkYellow
    $clusterEvents | Select-Object -First 25 | Format-Table -AutoSize -Property TimeCreated, ID, ProviderName, LevelDisplayName, Message
    Write-Host "Showing 25 of $($clusterEvents.Count) Total Cluster Events" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "No Failover Cluster events found." -ForegroundColor Green
}

# Export to CSV for further analysis
$csvPath = "$env:USERPROFILE\Desktop\EventLog_Report_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').csv"
Write-Host "Exporting detailed report to: $csvPath" -ForegroundColor Yellow

$allEvents = @()
$allEvents += $systemEvents | Select-Object TimeGenerated, EventID, Source, EntryType, Message
$allEvents += $appEvents | Select-Object TimeGenerated, EventID, Source, EntryType, Message
$allEvents += $hypervEvents | Select-Object @{Name='TimeGenerated';Expression={$_.TimeCreated}}, @{Name='EventID';Expression={$_.ID}}, @{Name='Source';Expression={$_.ProviderName}}, @{Name='EntryType';Expression={$_.LevelDisplayName}}, Message
$allEvents += $clusterEvents | Select-Object @{Name='TimeGenerated';Expression={$_.TimeCreated}}, @{Name='EventID';Expression={$_.ID}}, @{Name='Source';Expression={$_.ProviderName}}, @{Name='EntryType';Expression={$_.LevelDisplayName}}, Message

if ($allEvents) {
    $allEvents | Export-Csv -Path $csvPath -NoTypeInformation -Force
    Write-Host "Report exported successfully!" -ForegroundColor Green
} else {
    Write-Host "No events to export." -ForegroundColor Yellow
}
