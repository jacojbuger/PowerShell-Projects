<#
.SYNOPSIS
    Finds which VM (if any) owns a given MAC address. Runs locally by default.
    Optionally targets remote servers and/or whole clusters by name from one machine.

.PARAMETER Mac
    The MAC address to search for (dashes, colons, or no separators all work).

.PARAMETER ComputerName
    Optional list of individual Hyper-V hosts to query remotely instead of local-only.

.PARAMETER ClusterName
    Optional list of cluster names - each cluster's current live member nodes are
    auto-discovered and added to the search. Use this instead of listing every node
    by hand when you just want "search cluster X".

.EXAMPLE
    .\Find-VMByMac.ps1 -Mac "00-15-5d-ca-0b-43"
    # Local-only, run this way on a node you can't reach remotely (e.g. paused/evicted)

.EXAMPLE
    .\Find-VMByMac.ps1 -Mac "00-15-5d-ca-0b-43" -ClusterName APP-CLUS, CLUSTER-01
    # From one workstation, searches every live node in both named clusters

.EXAMPLE
    .\Find-VMByMac.ps1 -Mac "00-15-5d-ca-0b-43" -ComputerName NODE-01, SERV-04
    # From one workstation, searches specific named servers only
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Mac,

    [string[]]$ComputerName,

    [string[]]$ClusterName
)

$target = ($Mac -replace '[:\-]', '').ToUpper()

# Build the target node list: local-only unless -ComputerName or -ClusterName given
$targets = @()
if ($ComputerName) { $targets += $ComputerName }
foreach ($cluster in $ClusterName) {
    try {
        $members = (Get-ClusterNode -Cluster $cluster -ErrorAction Stop | Where-Object State -eq 'Up').Name
        Write-Host "Cluster '$cluster' -> $($members.Count) live node(s): $($members -join ', ')" -ForegroundColor DarkGray
        $targets += $members
    }
    catch {
        Write-Host "Could not query cluster '$cluster': $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
$targets = $targets | Select-Object -Unique
if (-not $targets) { $targets = @($env:COMPUTERNAME) }   # default: local only

$anyHit = $false

foreach ($node in $targets) {
    Write-Host "`n=== Searching $node for MAC $Mac ===" -ForegroundColor Cyan

    try {
        $params = if ($node -eq $env:COMPUTERNAME) { @{} } else { @{ ComputerName = $node } }
        $vms = Get-VM @params -ErrorAction Stop
    }
    catch {
        Write-Host "  UNREACHABLE or access denied: $($_.Exception.Message)" -ForegroundColor Yellow
        continue
    }

    $found = $vms | Get-VMNetworkAdapter | ForEach-Object {
        [PSCustomObject]@{
            Host        = $node
            VMName      = $_.VMName
            AdapterName = $_.Name
            MacAddress  = ($_.MacAddress -replace '(..)(?!$)', '$1-')
            IPAddresses = $_.IPAddresses -join ', '
            Match       = (($_.MacAddress -replace '[:\-]', '').ToUpper() -eq $target)
        }
    }

    $hit = $found | Where-Object Match
    if ($hit) {
        $anyHit = $true
        Write-Host "  FOUND" -ForegroundColor Green
        $hit | Format-Table Host, VMName, AdapterName, MacAddress, IPAddresses -AutoSize
    }
    else {
        Write-Host "  Not found ($(@($found).Count) VM adapters checked)." -ForegroundColor DarkGray
    }
}

if (-not $anyHit) {
    Write-Host "`nNo match found across $(@($targets).Count) node(s) searched." -ForegroundColor Yellow
}
