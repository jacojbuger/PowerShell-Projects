<#
.SYNOPSIS
    Validates all active iSCSI sessions and connections on dedicated iSCSI NICs.

.DESCRIPTION
    Checks that iSCSI sessions are online and connections are healthy on dedicated iSCSI network.
    Ignores LAN traffic. Safe, read-only health check. No sessions are disconnected or modified.
#>

Write-Host "=== iSCSI Session Validation ===" -ForegroundColor Cyan

$svc = Get-Service -Name MSiSCSI -ErrorAction SilentlyContinue
if ((-not $svc) -or ($svc.Status -ne 'Running')) {
    Write-Host "MSiSCSI service is NOT running - sessions cannot be validated." -ForegroundColor Red
    return
}

$sessions = @(Get-IscsiSession)
if ($sessions.Count -eq 0) {
    Write-Host "No active iSCSI sessions found." -ForegroundColor Yellow
    return
}

$allConnections = @(Get-IscsiConnection)
Write-Host "Found $($sessions.Count) sessions and $($allConnections.Count) connections on dedicated iSCSI network.`n" -ForegroundColor Cyan

$iscsiSubnets = @('172.1.100.', '172.1.101.', '172.2.200.', '172.2.201.')
Write-Host "Validating iSCSI subnet(s): $($iscsiSubnets -join ', ')`n" -ForegroundColor Cyan

$results = @()

foreach ($session in $sessions) {
    $sessionID   = $session.SessionIdentifier
    $targetIQN   = $session.TargetNodeAddress
    $isConnected = $session.IsConnected
    $connCount   = $session.NumberOfConnections

    $status = "Healthy"
    $issues = @()

    if (-not $isConnected) {
        $status = "Critical"
        $issues += "Session is NOT connected."
    }

    if ($connCount -lt 1) {
        $status = "Critical"
        $issues += "Session reports zero connections."
    }

    $connDetails = @()
    foreach ($conn in $allConnections) {
        $initiatorAddr = $conn.InitiatorAddress
        $targetAddr = $conn.TargetAddress

        $isIscsiSubnet = $false
        foreach ($subnet in $iscsiSubnets) {
            if ($initiatorAddr -like "$subnet*") {
                $isIscsiSubnet = $true
                break
            }
        }

        if ($isIscsiSubnet) {
            $connStatus = "OK"
            if ([string]::IsNullOrEmpty($initiatorAddr) -or [string]::IsNullOrEmpty($targetAddr)) {
                $connStatus = "MISSING_ADDR"
                if ($status -ne "Critical") { $status = "Warning" }
                $issues += "Connection has missing address information."
            }

            $connDetails += "$initiatorAddr -> $targetAddr [$connStatus]"
        }
    }

    if ($issues.Count -eq 0 -and $isConnected -and $connCount -ge 1) {
        $issues = @("Session is fully online and operational.")
    }

    $results += [pscustomobject]@{
        SessionID         = $sessionID.Substring(0, [Math]::Min(16, $sessionID.Length))
        TargetIQN         = $targetIQN
        Connected         = $isConnected
        Connections       = $connCount
        Status            = $status
        Details           = ($issues -join " ")
        ConnectionPaths   = if ($connDetails.Count -gt 0) { $connDetails -join " | " } else { "None" }
    }
}

$results | Format-Table -AutoSize -Wrap

Write-Host "`nSummary:" -ForegroundColor Cyan
$healthy = ($results | Where-Object { $_.Status -eq "Healthy" }).Count
$warning = ($results | Where-Object { $_.Status -eq "Warning" }).Count
$critical = ($results | Where-Object { $_.Status -eq "Critical" }).Count

Write-Host "  Healthy: $healthy  Warning: $warning  Critical: $critical" -ForegroundColor Green

if ($critical -gt 0) {
    Write-Host "`n*** ALERT: Critical issues detected ***" -ForegroundColor Red
} elseif ($warning -gt 0) {
    Write-Host "`nWarnings detected - review Details column." -ForegroundColor Yellow
} else {
    Write-Host "`nAll iSCSI sessions operational." -ForegroundColor Green
}

Write-Host "`nValidation Complete." -ForegroundColor Green
