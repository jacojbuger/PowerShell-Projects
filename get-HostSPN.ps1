# Check computer account and display its SPNs
$computerName = "KDC-ALLOY"
try {
    $computer = Get-ADComputer -Identity $computerName -Properties servicePrincipalName
    Write-Host "Computer found: $($computer.Name)" -ForegroundColor Green
    Write-Host "Distinguished Name: $($computer.DistinguishedName)" -ForegroundColor Gray
    Write-Host "`nConfigured SPNs:" -ForegroundColor Cyan
    if ($computer.servicePrincipalName) {
        $computer.servicePrincipalName | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "  No SPNs configured" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
