### Step 2: IMMEDIATELY Apply NTLM Blocking (Before Joining Any Systems)

## Critical:** Apply these settings BEFORE joining any member servers.

# Apply NTLM restrictions via registry immediately after DC promotion
$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0"

# Block NTLM receiving
Set-ItemProperty -Path $RegPath -Name "RestrictReceivingNTLMTraffic" -Value 2 -Type DWord

# Block NTLM sending  
Set-ItemProperty -Path $RegPath -Name "RestrictSendingNTLMTraffic" -Value 2 -Type DWord

# Set highest LM compatibility level (NTLMv2 only if NTLM somehow gets through)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" `
    -Name "LmCompatibilityLevel" -Value 5 -Type DWord

# DC-specific: Enforce LDAP channel binding
$DCPath = "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"
Set-ItemProperty -Path $DCPath -Name "LdapEnforceChannelBinding" -Value 2 -Type DWord

# DC-specific: Require LDAP signing
Set-ItemProperty -Path $DCPath -Name "LDAPServerIntegrity" -Value 2 -Type DWord

Write-Host "✓ NTLM blocked on Domain Controller" -ForegroundColor Green
Write-Host "⚠ Reboot required for full effect" -ForegroundColor Yellow
