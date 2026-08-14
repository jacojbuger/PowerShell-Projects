# AD Password Age Report
# This script retrieves password age information for all AD users and exports to CSV

# Import Active Directory module
Import-Module ActiveDirectory

# Set output file path
$OutputPath = "C:\reports\AD_Password_Report.csv"

# Create output directory if it doesn't exist
$OutputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "Retrieving Active Directory user information..." -ForegroundColor Cyan

# Get all enabled AD users with password properties
$Users = Get-ADUser -Filter {Enabled -eq $true} -Properties `
    SamAccountName, `
    PasswordLastSet, `
    PasswordNeverExpires, `
    whenCreated, `
    whenChanged | Select-Object `
    @{Name="Username";Expression={$_.SamAccountName}},
    @{Name="PasswordLastReset";Expression={
        if ($_.PasswordLastSet) {
            $_.PasswordLastSet.ToString("yyyy-MM-dd HH:mm:ss")
        } else {
            "Never"
        }
    }},
    @{Name="ObjectCreated";Expression={$_.whenCreated.ToString("yyyy-MM-dd HH:mm:ss")}},
    @{Name="ObjectLastModified";Expression={$_.whenChanged.ToString("yyyy-MM-dd HH:mm:ss")}},
    @{Name="PasswordExpires";Expression={
        if ($_.PasswordNeverExpires) {
            "No"
        } else {
            "Yes"
        }
    }}

# Export to CSV
$Users | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "Report generated successfully!" -ForegroundColor Green
Write-Host "Total users processed: $($Users.Count)" -ForegroundColor Yellow
Write-Host "Output file: $OutputPath" -ForegroundColor Yellow
Write-Host "`nOpening the CSV file..." -ForegroundColor Cyan

# Open the CSV file
Invoke-Item $OutputPath
