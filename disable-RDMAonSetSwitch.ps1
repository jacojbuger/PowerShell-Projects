<#
.SYNOPSIS
    Clear cluster validation RDMA warnings on Server-HPV-04.
    Disables RDMA on SET physical uplinks and all host vNICs.
#>

$ErrorActionPreference = "Stop"
$Node = $env:COMPUTERNAME

# Confirm actual adapter aliases before proceeding
Write-Host "[$Node] Current adapter inventory:" -ForegroundColor Cyan
Get-NetAdapter | Sort-Object Name | 
    Select-Object Name, InterfaceDescription, Status, LinkSpeed |
    Format-Table -AutoSize

# --- Physical SET uplinks ---
Write-Host "[$Node] Disabling RDMA on SET physical uplinks..." -ForegroundColor Cyan
foreach ($nic in @("LAN1", "LAN2")) {
    Disable-NetAdapterRdma -Name $nic -Confirm:$false
    Write-Host "  ✓ $nic" -ForegroundColor Green
}

# --- Synthetic host vNICs ---
Write-Host "[$Node] Disabling RDMA on host vNICs..." -ForegroundColor Cyan
foreach ($vnic in @("vLAN", "vLM")) {
    Disable-NetAdapterRdma -Name $vnic -Confirm:$false
    Write-Host "  ✓ $vnic" -ForegroundColor Green
}

# --- Verify ---
Write-Host "`n[$Node] Post-fix RDMA state:" -ForegroundColor Cyan
Get-NetAdapterRdma | Sort-Object Name |
    Format-Table Name, Enabled, Operational, RdmaCapable -AutoSize
