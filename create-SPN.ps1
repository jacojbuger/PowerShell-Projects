Import-Module ActiveDirectory
$svcAccount = "gMSA-REDIS"  # Just the account name, no domain prefix
$spns = @(
  "REDIS/kdc-redis.domainname.lab",
  "REDIS/KDC-REDIS"
)
Set-ADServiceAccount -Identity $svcAccount -Add @{
    servicePrincipalName = $spns
}
