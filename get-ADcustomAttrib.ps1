<#
.SYNOPSIS
    Reports how many users in a given OU already have a value in each of
    extensionAttribute1-15, so you can pick an unused slot with confidence.
.NOTES
    Author  : Jaco Burger / IT
    Version : 1.0.0
    Compatibility: Windows PowerShell 5.1
#>

[CmdletBinding()]
param(
    [string]$OU = "OU=IT,DC=DomainName,DC=Local"
)

Import-Module ActiveDirectory -ErrorAction Stop

$attrNames = 1..15 | ForEach-Object { "extensionAttribute$_" }
$users = Get-ADUser -SearchBase $OU -Filter * -Properties $attrNames

$summary = foreach ($attr in $attrNames) {
    $populated = $users | Where-Object { -not [string]::IsNullOrWhiteSpace($_.$attr) }
    [pscustomobject]@{
        Attribute      = $attr
        InUseCount     = $populated.Count
        SampleValues   = ($populated | Select-Object -First 3 -ExpandProperty $attr) -join '; '
    }
}

$summary | Format-Table -AutoSize
