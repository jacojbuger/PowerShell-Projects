<#
.SYNOPSIS
    Reset-WindowsUpdate.ps1 - Full Windows Update component remediation.
    Use at own RISK!!!

.DESCRIPTION
    Forcefully resets the Windows Update stack:
      1. Stops + temporarily disables WU services (defeats trigger-start restarts)
      2. Purges BITS job queue (qmgr*.dat) and cancels all BITS jobs
      3. Renames SoftwareDistribution (update cache + datastore + history)
      4. Renames catroot2 (crypto catalog cache)
      5. Clears Delivery Optimization cache
      6. Resets WSUS/MECM client identity (SusClientId) to force fresh registration
      7. Optional: service security descriptor reset, DLL re-registration,
         Winsock/WinHTTP reset, DISM + SFC component store repair
      8. Restarts services and forces a fresh detection cycle

.PARAMETER ResetSecurityDescriptors
    Restore default SDDL on bits + wuauserv (only if SDs were tampered with).

.PARAMETER ReRegisterDlls
    Re-register legacy WU COM DLLs. Mostly no-op on Server 2016+, harmless.

.PARAMETER ResetWinsock
    netsh winsock reset + winhttp proxy reset. REQUIRES REBOOT. Off by default.

.PARAMETER RunDismRepair
    Run DISM /RestoreHealth + SFC /scannow after the reset (slow, 15-45 min).

.PARAMETER SkipClientIdReset
    Keep SusClientId. Use if you do NOT want the client re-registering
    against WSUS/MECM SUP as a "new" client.

.PARAMETER NoScan
    Do not trigger a detection scan at the end.

.PARAMETER CollectLogs
    Collect a diagnostics bundle (update history + HResults, queued updates,
    WU client events, CBS.log error extraction, merged WindowsUpdate.log)
    into C:\Logs\WUDiag_<timestamp> BEFORE resetting.

.PARAMETER DiagnoseOnly
    Collect the diagnostics bundle and stop. No reset is performed.
    ALWAYS run this first on a box failing installs - the reset wipes
    update history, destroying the failure HResults you need.

.NOTES
    Version : 1.1.0
    Changes : 1.1.0 - Added -CollectLogs / -DiagnoseOnly diagnostics bundle
                      (history HResults, queued updates, WU events, CBS errors,
                      merged WindowsUpdate.log). Reset now also purges USOShared
                      orchestrator state for a true blank slate.
              1.0.3 - Host-aware exit: 'exit' killed the host when run in ISE or
                      dot-sourced/pasted into a console (looked like a crash).
                      Now returns in interactive hosts, exits only under -File.
              1.0.2 - Non-blocking service stop (sc.exe + poll) replaces blocking
                      Stop-Service which hung indefinitely on cryptsvc STOP_PENDING.
                      Guarded process-kill escalation for stuck sole-service svchost.
              1.0.1 - dosvc handled stop-only (Server 2019/2022 locked SD denies
                      ChangeServiceConfig to Administrators); dosvc failures
                      downgraded to WARN (non-blocking).
    Author  : Jaco Burger / IT
    Target  : PowerShell 5.1, Server 2016-2025, Windows 10/11
    Run     : Elevated. Reboot recommended after completion.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -DiagnoseOnly
    Evidence collection only - run this FIRST when installs fail near 100%.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1
    Standard remediation: cache purge, BITS purge, client ID reset, rescan.

.EXAMPLE
    .\Reset-WindowsUpdate.ps1 -CollectLogs -RunDismRepair -NoScan
    Capture evidence, reset, repair component store, no scan (pre-reboot mode).
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$ResetSecurityDescriptors,
    [switch]$ReRegisterDlls,
    [switch]$ResetWinsock,
    [switch]$RunDismRepair,
    [switch]$SkipClientIdReset,
    [switch]$NoScan,
    [switch]$CollectLogs,
    [switch]$DiagnoseOnly
)

#region ── Configuration ─────────────────────────────────────────────────────
$Script:Version   = '1.1.0'
$Script:LogDir    = 'C:\Logs'
$Script:LogFile   = Join-Path $LogDir ("Reset-WindowsUpdate_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Script:Stamp     = Get-Date -Format 'yyyyMMddHHmmss'
$Script:ErrCount  = 0
$Script:WarnCount = 0

# Service stop order matters: consumers first, cryptsvc last.
$Script:WUServices = @('wuauserv', 'UsoSvc', 'bits', 'dosvc', 'cryptsvc')

# Services whose security descriptor denies ChangeServiceConfig to Administrators
# on Server 2019/2022 - stop-only, never Set-Service, failures are non-blocking.
$Script:StopOnlyServices = @('dosvc')
#endregion

#region ── Logging ───────────────────────────────────────────────────────────
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    switch ($Level) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow; $Script:WarnCount++ }
        'ERROR' { Write-Host $line -ForegroundColor Red;    $Script:ErrCount++ }
        'STEP'  { Write-Host "`n$line" -ForegroundColor Cyan }
        default { Write-Host $line -ForegroundColor Gray }
    }
    Add-Content -Path $Script:LogFile -Value $line -ErrorAction SilentlyContinue
}
#endregion

#region ── Helper functions ──────────────────────────────────────────────────
function Stop-WUService {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Log "Service '$Name' not present - skipping" 'WARN'; return }

    $stopOnly = $Script:StopOnlyServices -contains $Name
    try {
        if (-not $stopOnly) {
            # Disable first so trigger-start cannot resurrect it mid-purge.
            # Skipped for stop-only services (locked SD denies ChangeServiceConfig).
            Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        }

        if ((Get-Service -Name $Name).Status -ne 'Stopped') {
            # Non-blocking stop request. Stop-Service blocks indefinitely on
            # STOP_PENDING (e.g. cryptsvc mid catalog rebuild) - never use it here.
            & sc.exe stop $Name | Out-Null
        }

        # Poll up to 60s for full stop
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ((Get-Service -Name $Name).Status -ne 'Stopped' -and $sw.Elapsed.TotalSeconds -lt 60) {
            Start-Sleep -Seconds 2
        }

        if ((Get-Service -Name $Name).Status -ne 'Stopped' -and -not $stopOnly) {
            # Escalation: kill the host process, but ONLY if this service is the
            # sole occupant of its svchost (true for cryptsvc on Server 2022 with
            # split service hosting). Never kill a shared svchost.
            $svcPid = (Get-CimInstance Win32_Service -Filter "Name='$Name'").ProcessId
            if ($svcPid -gt 0) {
                $cohabitants = @(Get-CimInstance Win32_Service -Filter "ProcessId=$svcPid")
                if ($cohabitants.Count -eq 1) {
                    Write-Log "Service '$Name' stuck in $((Get-Service $Name).Status) - killing sole-service host PID $svcPid" 'WARN'
                    Stop-Process -Id $svcPid -Force -ErrorAction Stop
                    Start-Sleep -Seconds 3
                }
                else {
                    Write-Log ("Service '{0}' stuck but shares PID {1} with: {2} - refusing to kill shared svchost" -f `
                        $Name, $svcPid, (($cohabitants.Name | Where-Object { $_ -ne $Name }) -join ', ')) 'ERROR'
                }
            }
        }

        if ((Get-Service -Name $Name).Status -eq 'Stopped') {
            if ($stopOnly) { Write-Log "Stopped (stop-only, not disabled): $Name" 'OK' }
            else           { Write-Log "Stopped + disabled: $Name" 'OK' }
        }
        else {
            Write-Log "Service '$Name' did not stop within 60s - folder rename may fail" 'WARN'
        }
    }
    catch {
        if ($stopOnly) {
            Write-Log "Could not stop '$Name' (non-blocking): $($_.Exception.Message)" 'WARN'
        }
        else {
            Write-Log "Failed to stop '$Name': $($_.Exception.Message)" 'ERROR'
        }
    }
}

function Restore-WUService {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$StartupType
    )
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    $stopOnly = $Script:StopOnlyServices -contains $Name
    try {
        if (-not $stopOnly) {
            Set-Service -Name $Name -StartupType $StartupType -ErrorAction Stop
        }
        if ((Get-Service -Name $Name).Status -ne 'Running') {
            Start-Service -Name $Name -ErrorAction Stop
        }
        if ($stopOnly) { Write-Log "Started (startup type untouched): $Name" 'OK' }
        else           { Write-Log "Restored ($StartupType) + started: $Name" 'OK' }
    }
    catch {
        if ($stopOnly) {
            Write-Log "Could not start '$Name' (demand-start, non-blocking): $($_.Exception.Message)" 'WARN'
        }
        else {
            Write-Log "Failed to restore '$Name': $($_.Exception.Message)" 'ERROR'
        }
    }
}

function Test-NonInteractiveHost {
    # 'exit' at script scope terminates the HOST when running in ISE, or when the
    # script is dot-sourced / pasted into a console. Only hard-exit when launched
    # via powershell.exe -File (task scheduler, MECM, remoting). Callers must use:
    #   if (Test-NonInteractiveHost) { exit $code } else { return }
    if ($psISE) { return $false }
    if ($Host.Name -ne 'ConsoleHost') { return $false }
    return ([Environment]::GetCommandLineArgs() -join ' ') -match '-File'
}

function Invoke-WUDiagnostics {
    Write-Log 'DIAGNOSTICS: Collecting Windows Update failure evidence' 'STEP'
    $diagDir = Join-Path $Script:LogDir "WUDiag_$Script:Stamp"
    New-Item -Path $diagDir -ItemType Directory -Force | Out-Null

    $searcher = $null
    try {
        $session  = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
    }
    catch { Write-Log "WUA COM session failed: $($_.Exception.Message)" 'ERROR' }

    # 1. Update history with failure HResults - the key artefact for install failures
    if ($searcher) {
        try {
            $count = $searcher.GetTotalHistoryCount()
            if ($count -gt 0) {
                $resultMap = @{ 0 = 'NotStarted'; 1 = 'InProgress'; 2 = 'Succeeded'
                                3 = 'SucceededWithErrors'; 4 = 'Failed'; 5 = 'Aborted' }
                $history = foreach ($h in $searcher.QueryHistory(0, [Math]::Min($count, 50))) {
                    [PSCustomObject]@{
                        Date    = $h.Date
                        Result  = $resultMap[[int]$h.ResultCode]
                        HResult = ('0x{0:X8}' -f $h.HResult)
                        KB      = if ($h.Title -match '(KB\d{6,7})') { $Matches[1] } else { '' }
                        Title   = $h.Title
                    }
                }
                $history | Export-Csv -Path (Join-Path $diagDir 'UpdateHistory.csv') -NoTypeInformation
                $failures = @($history | Where-Object { $_.Result -in 'Failed', 'Aborted', 'SucceededWithErrors' })
                if ($failures.Count -gt 0) {
                    Write-Log "Recent install FAILURES (full list: UpdateHistory.csv):" 'WARN'
                    $failures | Select-Object -First 8 | ForEach-Object {
                        Write-Log ("  {0:yyyy-MM-dd HH:mm}  {1}  {2}  {3}" -f $_.Date, $_.HResult, $_.KB, $_.Title) 'WARN'
                    }
                    $topCode = ($failures | Group-Object HResult | Sort-Object Count -Descending |
                        Select-Object -First 1).Name
                    Write-Log "Dominant failure HResult: $topCode" 'WARN'
                }
                else { Write-Log 'No failures in retrievable update history' 'OK' }
            }
            else {
                Write-Log 'Update history empty (expected if SoftwareDistribution was recently reset)' 'WARN'
            }
        }
        catch { Write-Log "History query failed: $($_.Exception.Message)" 'ERROR' }

        # 2. Currently queued/applicable updates
        try {
            $pending = $searcher.Search('IsInstalled=0 and IsHidden=0').Updates
            Write-Log "Queued/applicable updates: $($pending.Count)"
            $list = foreach ($u in $pending) {
                [PSCustomObject]@{ KB = ($u.KBArticleIDs -join ','); Title = $u.Title }
            }
            if ($list) {
                $list | Export-Csv -Path (Join-Path $diagDir 'PendingUpdates.csv') -NoTypeInformation
                $list | ForEach-Object { Write-Log ("  KB{0}  {1}" -f $_.KB, $_.Title) }
            }
        }
        catch { Write-Log "Pending-update search failed: $($_.Exception.Message)" 'WARN' }
    }

    # 3. WindowsUpdateClient operational events (Id 20/25 = install failure with HResult)
    try {
        Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-WindowsUpdateClient/Operational'; Id = 20, 25, 31, 34
        } -MaxEvents 40 -ErrorAction Stop |
            Select-Object TimeCreated, Id, Message |
            Export-Csv -Path (Join-Path $diagDir 'WUClient_Events.csv') -NoTypeInformation
        Write-Log 'Exported WindowsUpdateClient failure events' 'OK'
    }
    catch { Write-Log 'No WindowsUpdateClient failure events found' }

    # 4. CBS.log error extraction - authoritative for installs failing at commit (~100%)
    $cbs = Join-Path $env:SystemRoot 'Logs\CBS\CBS.log'
    if (Test-Path -Path $cbs) {
        try {
            Copy-Item -Path $cbs -Destination (Join-Path $diagDir 'CBS.log') -Force
            $cbsErrors = Select-String -Path $cbs -Pattern ', Error\s' |
                Select-Object -Last 200 -ExpandProperty Line
            $cbsErrors | Set-Content -Path (Join-Path $diagDir 'CBS_Errors.txt')
            foreach ($line in ($cbsErrors | Select-Object -Last 5)) {
                Write-Log "  CBS: $($line.Substring(0, [Math]::Min($line.Length, 160)))" 'WARN'
            }
            Write-Log 'CBS.log copied; last 200 error lines -> CBS_Errors.txt' 'OK'
        }
        catch { Write-Log "CBS extraction failed: $($_.Exception.Message)" 'WARN' }
    }

    # 5. Merged WindowsUpdate.log from ETL traces
    try {
        Get-WindowsUpdateLog -LogPath (Join-Path $diagDir 'WindowsUpdate.log') -ErrorAction Stop | Out-Null
        Write-Log 'Merged WindowsUpdate.log generated' 'OK'
    }
    catch { Write-Log "Get-WindowsUpdateLog failed (symbol server blocked?): $($_.Exception.Message)" 'WARN' }

    Write-Log "Diagnostics bundle: $diagDir" 'OK'
}

function Rename-WithRetry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$NewName,
        [int]$Retries = 3
    )
    if (-not (Test-Path -Path $Path)) {
        Write-Log "Path not found (already clean?): $Path" 'WARN'
        return $true
    }
    for ($i = 1; $i -le $Retries; $i++) {
        try {
            Rename-Item -Path $Path -NewName $NewName -Force -ErrorAction Stop
            Write-Log "Renamed: $Path -> $NewName" 'OK'
            return $true
        }
        catch {
            Write-Log "Rename attempt $i/$Retries failed: $($_.Exception.Message)" 'WARN'
            Start-Sleep -Seconds 5
        }
    }
    # Fallback: purge contents in place
    Write-Log "Rename failed - falling back to in-place content purge of $Path" 'WARN'
    try {
        Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "In-place purge completed: $Path" 'OK'
        return $true
    }
    catch {
        Write-Log "In-place purge failed: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}
#endregion

#region ── Pre-flight ────────────────────────────────────────────────────────
if (-not (Test-Path -Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[ERROR] This script must run elevated. Aborting.' -ForegroundColor Red
    if (Test-NonInteractiveHost) { exit 1 } else { return }
}

Write-Log "Reset-WindowsUpdate v$Script:Version starting on $env:COMPUTERNAME" 'STEP'
Write-Log "OS: $((Get-CimInstance Win32_OperatingSystem).Caption) | PS: $($PSVersionTable.PSVersion)"
Write-Log "Switches: SDReset=$ResetSecurityDescriptors DLLs=$ReRegisterDlls Winsock=$ResetWinsock DISM=$RunDismRepair SkipClientId=$SkipClientIdReset NoScan=$NoScan"

# Record current startup types so we restore correctly afterwards
$Script:OriginalStartup = @{}
foreach ($name in $WUServices) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if ($svc) {
        $mode = (Get-CimInstance Win32_Service -Filter "Name='$name'").StartMode
        # Map WMI StartMode to Set-Service values
        $Script:OriginalStartup[$name] = switch ($mode) {
            'Auto'   { 'Automatic' }
            'Manual' { 'Manual' }
            default  { 'Manual' }
        }
    }
}

# Capture cache size before purge (evidence)
$sdPath = Join-Path $env:SystemRoot 'SoftwareDistribution'
if (Test-Path $sdPath) {
    $sdSizeGB = [math]::Round(((Get-ChildItem $sdPath -Recurse -Force -ErrorAction SilentlyContinue |
        Measure-Object Length -Sum).Sum / 1GB), 2)
    Write-Log "SoftwareDistribution current size: $sdSizeGB GB"
}
#endregion

#region ── Step 0 (optional): Diagnostics ───────────────────────────────────
if ($CollectLogs -or $DiagnoseOnly) {
    Invoke-WUDiagnostics
}
if ($DiagnoseOnly) {
    Write-Log 'DiagnoseOnly specified - no reset performed. Review the bundle before resetting.' 'STEP'
    if (Test-NonInteractiveHost) { exit 0 } else { return }
}
#endregion

#region ── Step 1: Cancel BITS jobs + stop services ─────────────────────────
Write-Log 'STEP 1: Cancelling BITS jobs and stopping WU services' 'STEP'

try {
    Get-BitsTransfer -AllUsers -ErrorAction SilentlyContinue |
        Remove-BitsTransfer -ErrorAction SilentlyContinue
    Write-Log 'All BITS transfer jobs cancelled' 'OK'
}
catch {
    Write-Log "BITS job cancellation: $($_.Exception.Message)" 'WARN'
}

foreach ($name in $WUServices) { Stop-WUService -Name $name }
#endregion

#region ── Step 2: Purge BITS queue files ───────────────────────────────────
Write-Log 'STEP 2: Purging BITS queue database (qmgr*.dat)' 'STEP'

$qmgrPath = Join-Path $env:ALLUSERSPROFILE 'Microsoft\Network\Downloader'
try {
    $qmgrFiles = Get-ChildItem -Path $qmgrPath -Filter 'qmgr*.dat' -Force -ErrorAction SilentlyContinue
    if ($qmgrFiles) {
        $qmgrFiles | Remove-Item -Force -ErrorAction Stop
        Write-Log "Deleted $($qmgrFiles.Count) qmgr*.dat file(s)" 'OK'
    }
    else {
        Write-Log 'No qmgr*.dat files found'
    }
}
catch {
    Write-Log "qmgr purge failed: $($_.Exception.Message)" 'ERROR'
}
#endregion

#region ── Step 3: Rename SoftwareDistribution + catroot2 ───────────────────
Write-Log 'STEP 3: Renaming SoftwareDistribution and catroot2' 'STEP'

# Remove stale .bak folders from previous runs first
foreach ($stale in @("$sdPath.bak*", (Join-Path $env:SystemRoot 'System32\catroot2.bak*'))) {
    Get-Item -Path $stale -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Removed stale backup: $($_.FullName)"
    }
}

$null = Rename-WithRetry -Path $sdPath -NewName "SoftwareDistribution.bak_$Stamp"
$null = Rename-WithRetry -Path (Join-Path $env:SystemRoot 'System32\catroot2') -NewName "catroot2.bak_$Stamp"

# USO orchestrator state - clears stuck download/install queue tracking.
# Safe only while UsoSvc is stopped (it is, from Step 1).
$usoState = Join-Path $env:ProgramData 'USOShared'
if (Test-Path -Path $usoState) {
    try {
        Get-ChildItem -Path $usoState -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log 'USOShared orchestrator state purged' 'OK'
    }
    catch { Write-Log "USOShared purge: $($_.Exception.Message)" 'WARN' }
}
#endregion

#region ── Step 4: Delivery Optimization cache ──────────────────────────────
Write-Log 'STEP 4: Clearing Delivery Optimization cache' 'STEP'

try {
    if (Get-Command -Name Delete-DeliveryOptimizationCache -ErrorAction SilentlyContinue) {
        Delete-DeliveryOptimizationCache -Force -ErrorAction Stop
        Write-Log 'Delivery Optimization cache cleared' 'OK'
    }
    else {
        Write-Log 'Delete-DeliveryOptimizationCache cmdlet not available on this OS - skipping' 'WARN'
    }
}
catch {
    Write-Log "DO cache clear: $($_.Exception.Message)" 'WARN'
}
#endregion

#region ── Step 5: Reset WSUS/MECM client identity ──────────────────────────
Write-Log 'STEP 5: Resetting update client identity registry values' 'STEP'

if ($SkipClientIdReset) {
    Write-Log 'SkipClientIdReset specified - leaving SusClientId intact'
}
else {
    $wuKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate'
    foreach ($value in @('SusClientId', 'SusClientIdValidation', 'PingID', 'AccountDomainSid')) {
        try {
            if (Get-ItemProperty -Path $wuKey -Name $value -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $wuKey -Name $value -Force -ErrorAction Stop
                Write-Log "Removed registry value: $value" 'OK'
            }
            else {
                Write-Log "Registry value not present: $value"
            }
        }
        catch {
            Write-Log "Failed to remove '$value': $($_.Exception.Message)" 'ERROR'
        }
    }
}
#endregion

#region ── Step 6 (optional): Service security descriptors ──────────────────
if ($ResetSecurityDescriptors) {
    Write-Log 'STEP 6: Resetting service security descriptors to defaults' 'STEP'
    # Microsoft-documented default SDDL for bits and wuauserv
    $sddl = @{
        bits     = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
        wuauserv = 'D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)'
    }
    foreach ($svcName in $sddl.Keys) {
        $result = & sc.exe sdset $svcName $sddl[$svcName] 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Log "SD reset: $svcName" 'OK' }
        else { Write-Log ("SD reset failed for {0}: {1}" -f $svcName, ($result -join ' ')) 'ERROR' }
    }
}
#endregion

#region ── Step 7 (optional): Re-register WU DLLs ───────────────────────────
if ($ReRegisterDlls) {
    Write-Log 'STEP 7: Re-registering Windows Update COM DLLs' 'STEP'
    $dlls = @(
        'atl.dll', 'urlmon.dll', 'mshtml.dll', 'shdocvw.dll', 'browseui.dll',
        'jscript.dll', 'vbscript.dll', 'scrrun.dll', 'msxml.dll', 'msxml3.dll',
        'msxml6.dll', 'actxprxy.dll', 'softpub.dll', 'wintrust.dll', 'dssenh.dll',
        'rsaenh.dll', 'gpkcsp.dll', 'sccbase.dll', 'slbcsp.dll', 'cryptdlg.dll',
        'oleaut32.dll', 'ole32.dll', 'shell32.dll', 'initpki.dll', 'wuapi.dll',
        'wuaueng.dll', 'wuaueng1.dll', 'wucltui.dll', 'wups.dll', 'wups2.dll',
        'wuweb.dll', 'qmgr.dll', 'qmgrprxy.dll', 'wucltux.dll', 'muweb.dll', 'wuwebv.dll'
    )
    $registered = 0
    foreach ($dll in $dlls) {
        $path = Join-Path "$env:SystemRoot\System32" $dll
        if (Test-Path -Path $path) {
            Start-Process -FilePath "$env:SystemRoot\System32\regsvr32.exe" `
                -ArgumentList "/s `"$path`"" -Wait -WindowStyle Hidden
            $registered++
        }
    }
    Write-Log "Re-registered $registered DLL(s) (missing DLLs are expected on modern OS builds)" 'OK'
}
#endregion

#region ── Step 8 (optional): Winsock / WinHTTP reset ───────────────────────
if ($ResetWinsock) {
    Write-Log 'STEP 8: Resetting Winsock catalog and WinHTTP proxy' 'STEP'
    & netsh winsock reset | Out-Null
    Write-Log 'Winsock reset issued - REBOOT REQUIRED to take effect' 'WARN'
    & netsh winhttp reset proxy | Out-Null
    Write-Log 'WinHTTP proxy reset to direct access' 'OK'
}
#endregion

#region ── Step 9: Restore + restart services ───────────────────────────────
Write-Log 'STEP 9: Restoring service startup types and starting services' 'STEP'

# Reverse order: cryptsvc back first
foreach ($name in ($WUServices[($WUServices.Count - 1)..0])) {
    if ($Script:OriginalStartup.ContainsKey($name)) {
        Restore-WUService -Name $name -StartupType $Script:OriginalStartup[$name]
    }
}
#endregion

#region ── Step 10 (optional): DISM + SFC repair ────────────────────────────
if ($RunDismRepair) {
    Write-Log 'STEP 10: DISM RestoreHealth + SFC (this takes 15-45 minutes)' 'STEP'
    try {
        & dism.exe /Online /Cleanup-Image /RestoreHealth
        if ($LASTEXITCODE -eq 0) { Write-Log 'DISM RestoreHealth completed' 'OK' }
        else { Write-Log "DISM exited with code $LASTEXITCODE - review C:\Windows\Logs\DISM\dism.log" 'ERROR' }

        & sfc.exe /scannow
        if ($LASTEXITCODE -eq 0) { Write-Log 'SFC scan completed' 'OK' }
        else { Write-Log "SFC exited with code $LASTEXITCODE - review C:\Windows\Logs\CBS\CBS.log" 'WARN' }
    }
    catch {
        Write-Log "DISM/SFC repair failed: $($_.Exception.Message)" 'ERROR'
    }
}
#endregion

#region ── Step 11: Force fresh detection ───────────────────────────────────
if (-not $NoScan) {
    Write-Log 'STEP 11: Forcing update detection cycle' 'STEP'

    # Legacy WSUS re-authorization (harmless no-op on non-WSUS clients)
    & wuauclt.exe /resetauthorization /detectnow 2>$null

    # Modern scan trigger
    $uso = Join-Path "$env:SystemRoot\System32" 'usoclient.exe'
    if (Test-Path -Path $uso) {
        & $uso StartScan
        Write-Log 'usoclient StartScan triggered' 'OK'
    }

    # COM fallback - works on all supported builds
    try {
        (New-Object -ComObject 'Microsoft.Update.AutoUpdate').DetectNow()
        Write-Log 'Microsoft.Update.AutoUpdate DetectNow() invoked' 'OK'
    }
    catch {
        Write-Log "COM DetectNow not available: $($_.Exception.Message)" 'WARN'
    }
}
#endregion

#region ── Summary ───────────────────────────────────────────────────────────
Write-Log 'SUMMARY' 'STEP'
Write-Log "Errors: $Script:ErrCount | Warnings: $Script:WarnCount"
Write-Log "Log file: $Script:LogFile"
Write-Log 'A reboot is recommended before validating update retrieval.' 'WARN'
Write-Log 'Old caches retained as *.bak_<timestamp> - delete after confirming WU is healthy.'
Write-Log 'Validate with: Get-WindowsUpdateLog (merged ETL) and check SoftwareDistribution recreated.'

$Script:ExitCode = if ($Script:ErrCount -gt 0) { 2 } else { 0 }
Write-Log "Exit code: $Script:ExitCode"
if (Test-NonInteractiveHost) { exit $Script:ExitCode } else { return }
#endregion
