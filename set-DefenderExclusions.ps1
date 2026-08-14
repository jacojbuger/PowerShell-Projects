# === CONFIGURATION ===
$GpoName = "Defender - Server Workload Exclusions"
$Extensions = @(
    # Veeam
    "vbk","vib","vrb","vbm","vbk.tmp","vib.tmp","vrb.tmp",
    "vpx","dat","idx","lck","cfg","restore","flr","mnt",
    # SQL Server
    "mdf","ndf","ldf","bak","trn","dif","bkp","sqb",
    "tmp","xel","xem","out",
    "fd","ndx","grm","fdc","fts",
    # SQL Server Reporting Services
    "rdl","rdlc","rsds","rss","pbix",
    # Hyper-V
    "vhd","vhdx","avhd","avhdx","vhds","vhdset",
    "vmcx","vmrs","vmgs","xml","bin","vsv","vmem","slp",
    # Hyper-V / Cluster
    "chk","csvlog","sys","etl","log",
    # VM / Shielded VM
    "iso","wim","pdk","vsc","hgs","meta"
)

# === SCRIPT START ===
Import-Module GroupPolicy -ErrorAction Stop

# Check if GPO exists
Write-Host "Checking for GPO: $GpoName" -ForegroundColor Cyan
$GPO = Get-GPO -Name $GpoName -ErrorAction SilentlyContinue
if (-not $GPO) { 
    Write-Error "GPO '$GpoName' not found. Aborting."
    exit 1
}
Write-Host "GPO found successfully." -ForegroundColor Green

$BaseKey = "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Extensions"
$SuccessCount = 0
$ErrorCount = 0

# Add all extensions to the GPO
foreach ($Ext in $Extensions) {
    try {
        Set-GPRegistryValue -Name $GpoName -Key $BaseKey -ValueName $Ext -Type String -Value "0" -ErrorAction Stop
        $SuccessCount++
        Write-Host "✓ Added: $Ext" -ForegroundColor Green
    }
    catch {
        $ErrorCount++
        Write-Host "✗ Failed: $Ext - $_" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n" -ForegroundColor Cyan
Write-Host "=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total extensions: $($Extensions.Count)" -ForegroundColor White
Write-Host "Successfully added: $SuccessCount" -ForegroundColor Green
Write-Host "Failed: $ErrorCount" -ForegroundColor $(if ($ErrorCount -gt 0) { "Red" } else { "Green" })

if ($SuccessCount -gt 0) {
    Write-Host "`nNext steps:" -ForegroundColor Yellow
    Write-Host "1. Run 'gpupdate /force' on target servers" -ForegroundColor White
    Write-Host "2. Verify exclusions applied: Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Extensions'" -ForegroundColor White
}
