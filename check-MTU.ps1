# Get-NicMTU.ps1
# Reports MTU size for all network adapters on a local or remote host
# Requires: PowerShell 5.1+, Run as Administrator for accurate results
# Fix: Handles LinkSpeed as string (e.g. "10 Gbps") or numeric (bytes)

param(
    [string[]]$ComputerName = $env:COMPUTERNAME,
    [switch]$IncludeDisabled,
    [switch]$ExportCsv,
    [string]$CsvPath = ".\NIC_MTU_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

function Resolve-LinkSpeed {
    param($RawSpeed)

    if ($null -eq $RawSpeed) { return "Unknown" }

    # Already a number (bytes/sec from CIM)
    if ($RawSpeed -is [int64] -or $RawSpeed -is [uint64] -or $RawSpeed -is [int32]) {
        if ($RawSpeed -ge 1GB) { return "$([math]::Round($RawSpeed / 1GB, 0)) Gbps" }
        if ($RawSpeed -ge 1MB) { return "$([math]::Round($RawSpeed / 1MB, 0)) Mbps" }
        return "$RawSpeed bps"
    }

    # String returned by some drivers (e.g. "10 Gbps", "1 Gbps", "100 Mbps")
    if ($RawSpeed -is [string]) {
        return $RawSpeed.Trim()
    }

    return "Unknown"
}

function Get-NicMTUInfo {
    param([string]$Computer)

    $results = @()

    try {
        $adapters = Get-NetAdapter -CimSession $Computer -ErrorAction Stop

        foreach ($adapter in $adapters) {

            if (-not $IncludeDisabled -and $adapter.Status -eq 'Disabled') { continue }

            $ipv4MTU = $null
            $ipv6MTU = $null

            $ipInterfaces = Get-NetIPInterface -CimSession $Computer `
                -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue

            foreach ($iface in $ipInterfaces) {
                if ($iface.AddressFamily -eq 'IPv4') { $ipv4MTU = $iface.NlMtu }
                if ($iface.AddressFamily -eq 'IPv6') { $ipv6MTU = $iface.NlMtu }
            }

            $jumboFlag = if     ($ipv4MTU -ge 9000)     { "YES [JUMBO]"    }
                         elseif ($ipv4MTU -eq 1500)      { "Standard"       }
                         elseif ($null   -eq $ipv4MTU)   { "Unknown"        }
                         else                             { "Non-Standard"   }

            $results += [PSCustomObject]@{
                ComputerName  = $Computer
                AdapterName   = $adapter.Name
                InterfaceDesc = $adapter.InterfaceDescription
                IfIndex       = $adapter.ifIndex
                MacAddress    = $adapter.MacAddress
                Status        = $adapter.Status
                LinkSpeed     = Resolve-LinkSpeed -RawSpeed $adapter.LinkSpeed
                IPv4_MTU      = if ($ipv4MTU) { $ipv4MTU } else { "N/A" }
                IPv6_MTU      = if ($ipv6MTU) { $ipv6MTU } else { "N/A" }
                JumboFrames   = $jumboFlag
                MediaType     = $adapter.MediaType
            }
        }
    } catch {
        Write-Warning "[$Computer] Error: $_"
    }

    return $results
}

# --- Main ---
$allResults = @()

foreach ($computer in $ComputerName) {
    Write-Host "`n[*] Querying: $computer" -ForegroundColor Cyan
    $allResults += Get-NicMTUInfo -Computer $computer
}

$allResults | Format-Table -AutoSize -Property `
    ComputerName, AdapterName, Status, LinkSpeed, IPv4_MTU, IPv6_MTU, JumboFrames, MacAddress

Write-Host "`n--- MTU Anomaly Summary ---" -ForegroundColor Yellow
$anomalies = $allResults | Where-Object { $_.IPv4_MTU -ne 1500 -and $_.IPv4_MTU -ne "N/A" }

if ($anomalies) {
    $anomalies | Format-Table -AutoSize -Property ComputerName, AdapterName, IPv4_MTU, JumboFrames
} else {
    Write-Host "All active adapters report standard MTU (1500)." -ForegroundColor Green
}

if ($ExportCsv) {
    $allResults | Export-Csv -Path $CsvPath -NoTypeInformation
    Write-Host "`n[+] Exported to: $CsvPath" -ForegroundColor Green
}
