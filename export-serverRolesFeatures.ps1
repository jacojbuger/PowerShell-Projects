# ==============================================================================
# Export Installed Roles and Features to CSV
# ==============================================================================
# Run this on the source server to export installed roles and features
# Usage: .\ExportRolesAndFeatures.ps1 -OutputPath "C:\backup\roles.csv"

param(
    [Parameter(Mandatory=$true)]
    [string]$OutputPath
)

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    exit
}

# Get all installed Windows Features
$features = Get-WindowsFeature | Where-Object { $_.Installed -eq $true } | Select-Object Name, DisplayName, Installed

# Export to CSV
$features | Export-Csv -Path $OutputPath -NoTypeInformation -Force
Write-Host "Successfully exported $(($features).Count) installed roles and features to: $OutputPath" -ForegroundColor Green
