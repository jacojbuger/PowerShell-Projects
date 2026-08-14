#Requires -Version 5.1
<#
.SYNOPSIS
    Checks registry uninstall entries and compares against EXE file version.

.DESCRIPTION
    Searches all four standard Uninstall registry hives for entries matching
    the supplied application display name and/or EXE filename.
    Extracts FileVersion and ProductVersion from the EXE on disk using
    [System.Diagnostics.FileVersionInfo] and performs a typed [System.Version]
    comparison against the registry DisplayVersion.

    All failures are caught silently - output is always clean.

.PARAMETER AppName
    Display name (partial match) to search in registry. E.g. "Greenshot"

.PARAMETER ExePath
    Full path to the primary EXE to read file version from.
    E.g. "C:\Program Files\Greenshot\Greenshot.exe"
    If omitted, the script attempts to resolve from InstallLocation or UninstallString.

.PARAMETER ExeFileName
    EXE filename (without path) to match inside UninstallString.
    E.g. "unins000.exe" — useful for Inno Setup installers where the
    uninstaller holds version metadata.

.EXAMPLE
    # Basic search by app name
    .\Get-AppVersionInfo.ps1 -AppName "Greenshot"

.EXAMPLE
    # App name + known EXE path
    .\Get-AppVersionInfo.ps1 -AppName "Greenshot" -ExePath "C:\Program Files\Greenshot\Greenshot.exe"

.EXAMPLE
    # Match by uninstaller exe name
    .\Get-AppVersionInfo.ps1 -AppName "Greenshot" -ExeFileName "unins000.exe"

.NOTES
    Registry hives searched:
      HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*         (x64)
      HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*  (x86)
      HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*         (x64)
      HKCU\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*  (x86)

    Version comparison uses [System.Version] for accurate numeric ordering.
    String fallback used when version cannot be parsed as System.Version.

    Author  : Jacobus 
    Version : 1.0
    Requires: PowerShell 5.1+, no elevation required for HKCU; HKLM needs no
              elevation for reads.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true,  HelpMessage = "Application display name (partial match)")]
    [string]$AppName,

    [Parameter(Mandatory = $false, HelpMessage = "Full path to EXE file to read version from")]
    [string]$ExePath,

    [Parameter(Mandatory = $false, HelpMessage = "EXE filename to match in UninstallString (e.g. unins000.exe)")]
    [string]$ExeFileName
)

$ErrorActionPreference = "Stop"
$ExitCode = 0

#region ── Helpers ────────────────────────────────────────────────────────────

function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $colours = @{ INFO = "Cyan"; WARN = "Yellow"; ERROR = "Red"; SUCCESS = "Green" }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp][$Level] $Message" -ForegroundColor $colours[$Level]
}

function Convert-ToVersion {
    <#
    .SYNOPSIS Safely converts a raw version string to [System.Version].
    Handles both "1.2.3.4" and legacy Win32 resource "1, 2, 3, 4" formats.
    #>
    param ([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return $null }
    try {
        # Normalise: replace commas/spaces used in Win32 VERSIONINFO resources
        $normalised = $Raw.Trim() -replace '[,\s]+', '.'
        # Strip any non-numeric suffix (e.g. "1.2.3 beta" -> "1.2.3")
        $normalised = ($normalised -split '-')[0]   # drop build metadata
        $normalised = [regex]::Match($normalised, '^[\d\.]+').Value
        if ($normalised -match '^\d+(\.\d+){1,3}$') {
            return [System.Version]$normalised
        }
    }
    catch { }
    return $null
}

function Get-ExeFileVersion {
    <#
    .SYNOPSIS Returns a structured object with EXE version info. Never throws.
    #>
    param ([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue)) {
        return $null
    }
    try {
        $vi = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
        return [PSCustomObject]@{
            FullPath        = $vi.FileName
            FileDescription = $vi.FileDescription
            CompanyName     = $vi.CompanyName
            FileVersion     = $vi.FileVersion
            ProductVersion  = $vi.ProductVersion
            FileVersionObj  = Convert-ToVersion -Raw $vi.FileVersion
            ProdVersionObj  = Convert-ToVersion -Raw $vi.ProductVersion
        }
    }
    catch {
        Write-Log "Failed to read version from '$Path': $_" -Level WARN
        return $null
    }
}

function Get-RegistryUninstallMatches {
    <#
    .SYNOPSIS Searches all four standard Uninstall hives. Never throws.
    #>
    param (
        [string]$DisplayNameFilter,
        [string]$ExeNameFilter
    )

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($path in $regPaths) {
        try {
            $hive = if ($path -like 'HKLM:*') { 'HKLM' } else { 'HKCU' }
            $arch = if ($path -like '*WOW6432*') { 'x86' } else { 'x64' }

            $entries = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                       Where-Object { $null -ne $_.DisplayName }

            foreach ($e in $entries) {
                $nameMatch = ($DisplayNameFilter) -and ($e.DisplayName -like "*$DisplayNameFilter*")
                $exeMatch  = ($ExeNameFilter)  -and ($e.UninstallString -like "*$ExeNameFilter*")

                if (-not ($nameMatch -or $exeMatch)) { continue }

                $results.Add([PSCustomObject]@{
                    Hive            = $hive
                    Architecture    = $arch
                    DisplayName     = $e.DisplayName
                    DisplayVersion  = if ($e.DisplayVersion) { $e.DisplayVersion } else { '(not set)' }
                    Publisher       = if ($e.Publisher)      { $e.Publisher }      else { '(not set)' }
                    InstallDate     = if ($e.InstallDate)    { $e.InstallDate }    else { '(not set)' }
                    InstallLocation = if ($e.InstallLocation){ $e.InstallLocation } else { $null }
                    UninstallString = if ($e.UninstallString){ $e.UninstallString } else { $null }
                    RegistryKey     = ($path -replace '\\\*$') + '\' + $e.PSChildName
                    VersionObj      = Convert-ToVersion -Raw $e.DisplayVersion
                    MatchedBy       = if ($nameMatch -and $exeMatch) { 'Name + UninstallString' }
                                      elseif ($nameMatch) { 'DisplayName' }
                                      else                { 'UninstallString' }
                })
            }
        }
        catch {
            # Silent: HKCU WOW6432 may not exist on all systems; HKCU inaccessible as SYSTEM
        }
    }

    return $results
}

function Resolve-ExeFromRegistryEntry {
    <#
    .SYNOPSIS Attempts to locate the EXE from registry InstallLocation or UninstallString.
    #>
    param (
        [PSCustomObject]$RegEntry,
        [string]$AppNameHint,
        [string]$ExeFileNameHint
    )

    # Candidate EXE names to try inside InstallLocation
    $candidates = @()
    if ($ExeFileNameHint) { $candidates += $ExeFileNameHint }
    if ($AppNameHint)     { $candidates += "$AppNameHint.exe" }

    if ($RegEntry.InstallLocation -and (Test-Path $RegEntry.InstallLocation -ErrorAction SilentlyContinue)) {
        foreach ($c in $candidates) {
            $p = Join-Path $RegEntry.InstallLocation $c
            if (Test-Path $p -ErrorAction SilentlyContinue) {
                Write-Log "Resolved EXE from InstallLocation: $p" -Level INFO
                return $p
            }
        }
    }

    # Fall back to extracting path from UninstallString
    if ($RegEntry.UninstallString) {
        # Strip quotes and any CLI arguments (e.g. /SILENT)
        $raw = $RegEntry.UninstallString -replace '"', '' -replace '\s+/.*$', ''
        if (Test-Path $raw -ErrorAction SilentlyContinue) {
            Write-Log "Resolved EXE from UninstallString: $raw" -Level INFO
            return $raw
        }
    }

    return $null
}

#endregion

#region ── Main ───────────────────────────────────────────────────────────────

Write-Log "=== Get-AppVersionInfo ===" -Level INFO
Write-Log "AppName='$AppName'  ExeFileName='$ExeFileName'  ExePath='$ExePath'" -Level INFO
Write-Host ""

# ── 1. Registry Search ────────────────────────────────────────────────────────
Write-Log "Searching registry uninstall hives..." -Level INFO
$regMatches = Get-RegistryUninstallMatches -DisplayNameFilter $AppName -ExeNameFilter $ExeFileName

if ($regMatches.Count -eq 0) {
    Write-Log "No registry entry found for '$AppName'$(if($ExeFileName){" / '$ExeFileName'"})." -Level WARN
    Write-Host ""
    Write-Host " REGISTRY RESULT : NO ENTRY FOUND " -ForegroundColor Black -BackgroundColor Yellow
    Write-Host ""
} else {
    Write-Log "Found $($regMatches.Count) registry match(es)." -Level SUCCESS
    Write-Host ""
    Write-Host "=== Registry Matches ===" -ForegroundColor Cyan
    $regMatches | Format-Table -AutoSize -Property Hive, Architecture, DisplayName, DisplayVersion, Publisher, InstallDate, MatchedBy
    Write-Host "Registry Key(s):" -ForegroundColor DarkCyan
    $regMatches | ForEach-Object { Write-Host "  $($_.RegistryKey)" -ForegroundColor Gray }
    Write-Host ""
}

# ── 2. EXE File Version ───────────────────────────────────────────────────────
Write-Log "Resolving EXE file version..." -Level INFO

$exeInfo = $null
$resolvedPath = $null

if ($ExePath) {
    $resolvedPath = $ExePath
    Write-Log "Using supplied ExePath: $resolvedPath" -Level INFO
}
elseif ($regMatches.Count -gt 0) {
    $resolvedPath = Resolve-ExeFromRegistryEntry -RegEntry $regMatches[0] `
                        -AppNameHint $AppName -ExeFileNameHint $ExeFileName
}

if ($resolvedPath) {
    $exeInfo = Get-ExeFileVersion -Path $resolvedPath
}

if ($null -eq $exeInfo) {
    Write-Log "EXE file version could not be read. Provide -ExePath for accurate comparison." -Level WARN
    Write-Host " EXE FILE VERSION : NOT FOUND " -ForegroundColor Black -BackgroundColor Yellow
    Write-Host ""
} else {
    Write-Host "=== EXE File Version ===" -ForegroundColor Cyan
    [PSCustomObject]@{
        Path            = $exeInfo.FullPath
        FileDescription = $exeInfo.FileDescription
        CompanyName     = $exeInfo.CompanyName
        FileVersion     = $exeInfo.FileVersion
        ProductVersion  = $exeInfo.ProductVersion
    } | Format-List
}

# ── 3. Version Comparison ─────────────────────────────────────────────────────
if ($regMatches.Count -gt 0 -and $null -ne $exeInfo) {
    Write-Host "=== Version Comparison ===" -ForegroundColor Cyan
    Write-Host ""

    $compRows = foreach ($reg in $regMatches) {
        $status = "UNKNOWN"
        $note   = "One or both versions could not be parsed as System.Version"

        $regVer = $reg.VersionObj
        $exeVer = $exeInfo.FileVersionObj   # Primary: FileVersion
        # If FileVersion fails, try ProductVersion
        if ($null -eq $exeVer) { $exeVer = $exeInfo.ProdVersionObj }

        if ($regVer -and $exeVer) {
            $cmp = $exeVer.CompareTo($regVer)
            $status = switch ($true) {
                ($cmp -eq 0) { "MATCH"  }
                ($cmp -gt 0) { "EXE NEWER than Registry" }
                ($cmp -lt 0) { "REGISTRY NEWER than EXE" }
            }
            $note = "EXE [$exeVer]  vs  Registry [$regVer]"
        }
        elseif ($reg.DisplayVersion -ne '(not set)' -and $exeInfo.FileVersion) {
            # Fallback: raw string comparison
            $status = if ($reg.DisplayVersion.Trim() -eq $exeInfo.FileVersion.Trim()) {
                "MATCH (string)"
            } else {
                "MISMATCH (string) - versions differ or format incompatible"
            }
            $note = "EXE '$($exeInfo.FileVersion)'  vs  Registry '$($reg.DisplayVersion)'"
        }

        [PSCustomObject]@{
            App             = $reg.DisplayName
            Arch            = $reg.Architecture
            RegistryVersion = $reg.DisplayVersion
            EXEFileVersion  = if ($exeInfo.FileVersion)  { $exeInfo.FileVersion }  else { 'N/A' }
            EXEProductVer   = if ($exeInfo.ProductVersion){ $exeInfo.ProductVersion } else { 'N/A' }
            Status          = $status
        }
    }

    $compRows | Format-Table -AutoSize

    # Colour summary per row
    foreach ($r in $compRows) {
        $colour = switch -Wildcard ($r.Status) {
            "MATCH*"              { "Green"  }
            "EXE NEWER*"          { "Yellow" }
            "REGISTRY NEWER*"     { "Red"    }
            "MISMATCH*"           { "Red"    }
            default               { "Gray"   }
        }
        Write-Host ("  [{0}] {1}: {2}" -f $r.Arch, $r.App, $r.Status) -ForegroundColor $colour
    }
    Write-Host ""
}

Write-Log "Done." -Level SUCCESS
exit $ExitCode

#endregion
