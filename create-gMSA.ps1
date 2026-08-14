# ================================
# CONFIGURATION VARIABLES (edit this only)
# ================================
$gMSAName       = "gMSA-ALLOY"
$DNSHostName    = "gMSA-ALLOY.domainname.lab"
$ServiceOU      = "OU=MSA Groups,DC=domainname,DC=lab"
$GroupOU        = "OU=MSA Groups,DC=domainname,DC=lab"
$SecurityGroup  = "sgALLOY-Servers"
$Description    = "gMSA for Grafana service assignments"

# ================================
# CREATE SECURITY GROUP
# ================================
$existingGroup = Get-ADGroup -Filter "Name -eq '$SecurityGroup'" -ErrorAction SilentlyContinue
if (-not $existingGroup) {
    Write-Host "Creating security group: $SecurityGroup" -ForegroundColor Green
    New-ADGroup `
        -Name $SecurityGroup `
        -GroupScope DomainLocal `
        -GroupCategory Security `
        -Path $GroupOU `
        -Description "Hosts allowed to retrieve password for $gMSAName"
} else {
    Write-Host "Security group already exists: $SecurityGroup" -ForegroundColor Yellow
}

# ================================
# CREATE gMSA
# ================================
$existingGMSA = Get-ADServiceAccount -Filter "Name -eq '$gMSAName'" -ErrorAction SilentlyContinue
if (-not $existingGMSA) {
    Write-Host "Creating gMSA: $gMSAName" -ForegroundColor Green
    New-ADServiceAccount `
        -Name $gMSAName `
        -DNSHostName $DNSHostName `
        -Path $ServiceOU `
        -PrincipalsAllowedToRetrieveManagedPassword $SecurityGroup `
        -Description $Description
} else {
    Write-Host "gMSA already exists: $gMSAName" -ForegroundColor Yellow
}

# ================================
# ADD TO SECURITY GROUP - Modify members
# ================================
Write-Host "Adding to security group..." -ForegroundColor Green
Add-ADGroupMember `
    -Identity $SecurityGroup `
    -Members "KDC-BKP01$"

# Validate the gMSA
Write-Host "`nValidating gMSA configuration:" -ForegroundColor Cyan
Get-ADServiceAccount $gMSAName -Properties PrincipalsAllowedToRetrieveManagedPassword
