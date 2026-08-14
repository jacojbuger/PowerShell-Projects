# Prompt for account name
$accountInput = Read-Host "Enter the account name (user, group, or gMSA - can include or exclude $ for gMSA)"

# Try to resolve the account - handle gMSA with or without $
$accounts = $null
$sid = $null

# First try as-is
try {
    $ntAccount = New-Object System.Security.Principal.NTAccount($accountInput)
    $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
    Write-Host "Resolved: $($ntAccount.Value) -> $sid`n" -ForegroundColor Cyan
} catch {
    # If it's a gMSA without $, try adding it
    if (-not $accountInput.EndsWith('$')) {
        try {
            $accountWithDollar = "$accountInput`$"
            $ntAccount = New-Object System.Security.Principal.NTAccount($accountWithDollar)
            $sid = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
            Write-Host "Resolved as gMSA: $($ntAccount.Value) -> $sid`n" -ForegroundColor Cyan
        } catch {
            Write-Host "Could not resolve account '$accountInput'. Verify the account exists and use format DOMAIN\AccountName" -ForegroundColor Red
            exit
        }
    } else {
        Write-Host "Could not resolve account '$accountInput'. Verify the account exists and use format DOMAIN\AccountName" -ForegroundColor Red
        exit
    }
}

# Export security policy to temporary file
$tempFile = "$env:TEMP\secpolicy_$([guid]::NewGuid()).inf"
secedit /export /cfg $tempFile | Out-Null

# Read the policy file
$policyContent = Get-Content $tempFile

# Parse user rights assignments
$rightsAssigned = @()

foreach ($line in $policyContent) {
    if ($line -match "^Se.*Right\s*=\s*(.*)") {
        $right = $line.Split('=')[0].Trim()
        $accounts = $line.Split('=')[1].Trim()
        
        # Check if the SID is in the accounts list
        if ($accounts -like "*$sid*") {
            $rightsAssigned += [PSCustomObject]@{
                Right    = $right
                AssignedTo = $accounts
            }
        }
    }
}

# Display results
if ($rightsAssigned.Count -gt 0) {
    Write-Host "User Rights Assigned to '$accountInput':" -ForegroundColor Green
    Write-Host "=" * 80
    $rightsAssigned | Format-Table -AutoSize -Wrap
} else {
    Write-Host "No user rights assignments found for '$accountInput'" -ForegroundColor Yellow
}

# Clean up temporary file
Remove-Item $tempFile -Force
