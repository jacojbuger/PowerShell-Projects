# Get all TCP connections, group by OwningProcess ID, and sort to find the top 10 PIDs with the most connections
$top10Pids = Get-NetTCPConnection | Group-Object -Property OwningProcess | Sort-Object -Property Count -Descending | Select-Object -First 10 -Property Count, Name

Write-Host "Top 10 Processes by Connection Count:" -ForegroundColor Cyan
Write-Host "------------------------------------" -ForegroundColor Cyan

foreach ($process in $top10Pids) {
    # Get process name for the current PID
    $processName = (Get-Process -Id $process.Name -ErrorAction SilentlyContinue).ProcessName
    if (-not $processName) { $processName = "PID " + $process.Name + " (Name Unavailable)" }
    
    Write-Host "`nProcess: $processName (PID: $($process.Name)) - Connections: $($process.Count)" -ForegroundColor Green
    
    # List all connections for this specific process, selecting relevant properties
    Get-NetTCPConnection -OwningProcess $process.Name | Select-Object @{Name="Source IP"; Expression={$_.LocalAddress}},
                                                                  @{Name="Source Port"; Expression={$_.LocalPort}},
                                                                  @{Name="Destination IP"; Expression={$_.RemoteAddress}},
                                                                  @{Name="Destination Port"; Expression={$_.RemotePort}},
                                                                  State | Format-Table -AutoSize
}
