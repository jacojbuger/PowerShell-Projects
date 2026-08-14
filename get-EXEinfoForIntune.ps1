<#
.VERSION
    3.3 — PS5-compatible, portable EXE handling
.SYNOPSIS
    Collects metadata for Intune Win32 app configuration.
.DESCRIPTION
    Analyzes EXE, PE header, and registry to produce structured output.
    Supports installed and portable EXEs. Skips missing helper functions safely.
#>

[CmdletBinding()]
param(
    [string]$ExePath,
    [string]$ExportJson
)

try {
    # ────────────────────────────────
    # SECTION 0 — INPUT & VALIDATION
    # ────────────────────────────────
    if (-not $ExePath) {
        $ExePath = Read-Host "Enter the full path to the EXE you want to analyze"
    }

    if (-not (Test-Path -LiteralPath $ExePath)) {
        throw "File not found: $ExePath"
    }

    $file = Get-Item -LiteralPath $ExePath
    $versionInfo = $file.VersionInfo

    $output = [ordered]@{
        FilePath        = $ExePath
        FileName        = $file.Name
        FileVersion     = $versionInfo.FileVersion
        ProductName     = $versionInfo.ProductName
        PEArchitecture  = "Unknown"
        InstallerType   = "Unknown"
        RegistryHive    = $null
        RegistryArch    = $null
        RegistryKeyPath = $null
        SilentSwitch    = "UNKNOWN"
        UninstallCmd    = "UNKNOWN"
    }

    # ────────────────────────────────
    # SECTION 1 — PE HEADER & INSTALLER TYPE
    # ────────────────────────────────
    try {
        if (Get-Command Get-PEArchitecture -ErrorAction SilentlyContinue) {
            $output.PEArchitecture = Get-PEArchitecture -Path $ExePath
        }

        if (Get-Command Get-InstallerType -ErrorAction SilentlyContinue) {
            $output.InstallerType = Get-InstallerType -Path $ExePath
        }
    } catch {
        Write-Warning "PE Header / Installer detection failed: $_"
    }

    # ────────────────────────────────
    # SECTION 2 — REGISTRY SEARCH
    # ────────────────────────────────
    $uninstallHives = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*";             Hive = "HKLM"; Arch = "64-bit" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"; Hive = "HKLM"; Arch = "32-bit" },
        @{ Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*";             Hive = "HKCU"; Arch = "64-bit" }
    )

    $app = $null
    foreach ($hive in $uninstallHives) {
        $items = Get-ItemProperty -Path $hive.Path -ErrorAction SilentlyContinue
        if (-not $items) { continue }

        foreach ($item in $items) {
            $installLocation = if ($item.PSObject.Properties['InstallLocation']) { $item.InstallLocation } else { $null }
            $displayIcon     = if ($item.PSObject.Properties['DisplayIcon'])     { $item.DisplayIcon }     else { $null }
            $displayName     = if ($item.PSObject.Properties['DisplayName'])     { $item.DisplayName }     else { $null }

            $match = $false

            if ($installLocation -and $ExePath.StartsWith($installLocation.TrimEnd('\'), [System.StringComparison]::InvariantCultureIgnoreCase)) {
                $match = $true
            }
            elseif ($displayIcon -and $displayIcon -like "*$($file.Name)*") {
                $match = $true
            }
            elseif ($displayName -and $versionInfo.ProductName -and $displayName -like "*$($versionInfo.ProductName.Split(' ')[0])*") {
                $match = $true
            }

            if ($match) {
                $app = $item
                $output.RegistryHive    = $hive.Hive
                $output.RegistryArch    = $hive.Arch
                $output.RegistryKeyPath = $item.PSPath -replace "^Microsoft.PowerShell.Core\\Registry::", ""
                break
            }
        }

        if ($app) { break }
    }

    # ────────────────────────────────
    # SECTION 3 — HANDLE PORTABLE APPS
    # ────────────────────────────────
    if (-not $app) {
        # If no uninstall key, mark as portable
        $output.InstallerType   = "Portable"
        $output.RegistryHive    = "N/A"
        $output.RegistryArch    = "N/A"
        $output.RegistryKeyPath = "N/A"
        $output.SilentSwitch    = "N/A"
        $output.UninstallCmd    = "N/A"
    }

    # ────────────────────────────────
    # SECTION 4 — SILENT/UNINSTALL (if helpers exist)
    # ────────────────────────────────
    $rawUninstall = if ($app -and $app.PSObject.Properties.Match("UninstallString")) { $app.UninstallString } else { $null }

    if ($rawUninstall) {
        if (Get-Command Get-SilentInstallSwitch -ErrorAction SilentlyContinue) {
            try { $output.SilentSwitch = Get-SilentInstallSwitch -Type $output.InstallerType -UninstallStr $rawUninstall } catch {}
        }
        if (Get-Command Get-SilentUninstallCommand -ErrorAction SilentlyContinue) {
            try { $output.UninstallCmd = Get-SilentUninstallCommand -RawUninstall $rawUninstall -Type $output.InstallerType } catch {}
        }
    }

    # ────────────────────────────────
    # SECTION 5 — JSON EXPORT
    # ────────────────────────────────
    if ($ExportJson) {
        try {
            $output | ConvertTo-Json -Depth 5 | Out-File -FilePath $ExportJson -Encoding UTF8 -Force
            Write-Host "Exported: $ExportJson" -ForegroundColor Green
        } catch {
            Write-Warning "JSON export failed: $_"
        }
    }

    # ────────────────────────────────
    # FINAL OUTPUT
    # ────────────────────────────────
    $output
}
catch {
    Write-Error "Unexpected script error: $_"
}
