# ==============================================================================
# Import Roles and Features from CSV and Install on New Server
# ==============================================================================
# Run this on the destination server to install roles and features from CSV
# Usage: .\ImportRolesAndFeatures.ps1 -CsvPath "C:\backup\roles.csv"

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath
)

# Ensure running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "This script must be run as Administrator!" -ForegroundColor Red
    exit
}

# Verify CSV file exists
if (-not (Test-Path -Path $CsvPath)) {
    Write-Host "CSV file not found: $CsvPath" -ForegroundColor Red
    exit
}

# Import CSV
$features = Import-Csv -Path $CsvPath

# Track success and failures
$installed = @()
$failed = @()
$skipped = @()

Write-Host "Starting installation of $(($features).Count) roles and features..." -ForegroundColor Cyan

foreach ($feature in $features) {
    $featureName = $feature.Name
    $displayName = $feature.DisplayName
    
    # Skip if already installed
    if ((Get-WindowsFeature -Name $featureName).Installed) {
        Write-Host "Skipped (already installed): $displayName" -ForegroundColor Yellow
        $skipped += $featureName
        continue
    }
    
    try {
        Write-Host "Installing: $displayName..." -ForegroundColor Cyan
        Add-WindowsFeature -Name $featureName -ErrorAction Stop | Out-Null
        Write-Host "Installed successfully: $displayName" -ForegroundColor Green
        $installed += $featureName
    }
    catch {
        Write-Host "Failed to install: $displayName - Error: $($_.Exception.Message)" -ForegroundColor Red
        $failed += @{ Feature = $featureName; Error = $_.Exception.Message }
    }
}

# Summary Report
Write-Host "`n========== INSTALLATION SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Successfully Installed: $($installed.Count)" -ForegroundColor Green
Write-Host "Skipped (Already Installed): $($skipped.Count)" -ForegroundColor Yellow
Write-Host "Failed: $($failed.Count)" -ForegroundColor Red

if ($failed.Count -gt 0) {
    Write-Host "`nFailed Features:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $($_.Feature): $($_.Error)" }
}

Write-Host "`nNote: Some features may require a server restart to complete installation." -ForegroundColor Cyan
