$establishedConnections = Get-NetTCPConnection -State Established
$countEstablished = $establishedConnections.Count

Write-Host "Total number of Established TCP connections: $countEstablished"
