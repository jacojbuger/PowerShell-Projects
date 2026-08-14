<# 
.SYNOPSIS
  Validates Hyper-V NIC optimization state (VMQ / RSS / iSCSI / Broadcom)
  Screen output only.
#>

Write-Host "=== VALIDATION STARTED ===" -ForegroundColor Cyan

$iScsi = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Name -like "iSCSI*"
$vUplink = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Name -in @("LAN1","LAN2")
$broadcom = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object InterfaceDescription -match "Broadcom"

# ----------------------------
# Validate iSCSI NICs
# ----------------------------
Write-Host ""
Write-Host "--- Checking iSCSI NICs ---" -ForegroundColor Yellow

foreach ($nic in $iScsi) {

    $vmq = (Get-NetAdapterVmq -Name $nic.Name -ErrorAction SilentlyContinue).Enabled

    $vmqDriver = Get-NetAdapterAdvancedProperty -Name $nic.Name `
        -ErrorAction SilentlyContinue |
        Where-Object RegistryKeyword -match "VMQ" |
        Select-Object -First 1 -ExpandProperty DisplayValue

    try {
        $rssInfo = Get-NetAdapterRss -Name $nic.Name -ErrorAction Stop
        $rss = $rssInfo.Enabled
        $rssQueues = $rssInfo.NumberOfReceiveQueues
        $rssProfile = $rssInfo.Profile
    }
    catch {
        $rss = $false
        $rssQueues = 0
        $rssProfile = "Unsupported"
    }

    if ($vmq -eq $false -and $vmqDriver -match "Disabled") {
        Write-Host "$($nic.Name): VMQ disabled" -ForegroundColor Green
    }
    else {
        Write-Host "$($nic.Name): VMQ NOT disabled" -ForegroundColor Red
    }

    if ($rss) {
        Write-Host "$($nic.Name): RSS enabled" -ForegroundColor Green
    }
    else {
        Write-Host "$($nic.Name): RSS disabled or unsupported" -ForegroundColor Red
    }

    if ($rssQueues -le 8 -and $rssQueues -gt 0) {
        Write-Host "$($nic.Name): RSS queues = $rssQueues" -ForegroundColor Green
    }
    elseif ($rssQueues -eq 0) {
        Write-Host "$($nic.Name): RSS queues unavailable" -ForegroundColor Yellow
    }
    else {
        Write-Host "$($nic.Name): RSS queues too high ($rssQueues)" -ForegroundColor Red
    }

    if ($rssProfile -eq "NUMAStatic") {
        Write-Host "$($nic.Name): RSS profile NUMAStatic" -ForegroundColor Green
    }
    elseif ($rssProfile -eq "Unsupported") {
        Write-Host "$($nic.Name): RSS profile unsupported" -ForegroundColor Yellow
    }
    else {
        Write-Host "$($nic.Name): RSS profile $rssProfile" -ForegroundColor Red
    }
}

# ----------------------------
# Validate Hyper-V Uplinks
# ----------------------------
Write-Host ""
Write-Host "--- Checking Hyper-V Uplink NICs (LAN1/LAN2) ---" -ForegroundColor Yellow

foreach ($nic in $vUplink) {

    $vmq = (Get-NetAdapterVmq -Name $nic.Name -ErrorAction SilentlyContinue).Enabled

    try {
        $rss = (Get-NetAdapterRss -Name $nic.Name -ErrorAction Stop).Enabled
    }
    catch {
        $rss = $false
    }

    if (-not $rss) {
        Write-Host "$($nic.Name): RSS disabled" -ForegroundColor Green
    }
    else {
        Write-Host "$($nic.Name): RSS ENABLED" -ForegroundColor Red
    }

    if ($vmq) {
        Write-Host "$($nic.Name): VMQ enabled" -ForegroundColor Green
    }
    else {
        Write-Host "$($nic.Name): VMQ NOT enabled" -ForegroundColor Red
    }
}

# ----------------------------
# Validate Broadcom NICs
# ----------------------------
Write-Host ""
Write-Host "--- Checking Broadcom 1Gb NICs ---" -ForegroundColor Yellow

foreach ($nic in $broadcom) {
    if ($nic.Status -eq "Disabled") {
        Write-Host "$($nic.Name): Disabled" -ForegroundColor Green
    }
    else {
        Write-Host "$($nic.Name): ENABLED" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== VALIDATION COMPLETE ===" -ForegroundColor Cyan
