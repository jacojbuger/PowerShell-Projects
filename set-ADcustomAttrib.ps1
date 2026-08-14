<#
.SYNOPSIS
    Sets a single extensionAttribute value on every user in a target OU, for
    later use as an Exchange Online dynamic distribution group filter.
.DESCRIPTION
    Requires -AttributeNumber (1-15) and -Value explicitly — no default
    slot is assumed, since the right one depends on the audit script in
    Step 1 confirming it's actually free. Refuses to run if any in-scope
    user already has a different, non-blank value in that slot unless
    -Force is specified, to avoid silently overwriting an existing use of
    the same extensionAttribute for something else.
.NOTES
    Author   : Jaco Burger / companyname IT
    Version  : 1.0.2
    Changelog:
      1.0.0 - Initial version.
      1.0.1 - Start-Transcript forced with -WhatIf:$false. Under -WhatIf,
              Start-Transcript (itself ShouldProcess-aware) correctly skipped
              starting, but Stop-Transcript still ran unconditionally and
              errored with "the host is not currently transcribing." Also
              (incorrectly) added -WhatIf:$false to Stop-Transcript calls.
      1.0.2 - Removed -WhatIf:$false from Stop-Transcript — it doesn't
              support that parameter at all (unlike Start-Transcript) and
              errors with "parameter cannot be found." Left as plain
              Stop-Transcript, which now works correctly since
              Start-Transcript's -WhatIf:$false means a transcript is
              genuinely active by the time Stop-Transcript runs.
    Compatibility: Windows PowerShell 5.1
.EXAMPLE
    .\Set-OUCustomAttribute.ps1 -OU "OU=Users,OU=IT,DC=companyname,DC=Local" -AttributeNumber 1 -Value "PermStaff"
.EXAMPLE
    .\Set-OUCustomAttribute.ps1 -OU "OU=Users,..." -AttributeNumber 1 -Value "PermStaff" -Confirm:$false
    Skips the interactive Y/N prompt — for scheduled/unattended runs.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string]$OU,

    [Parameter(Mandatory)]
    [ValidateRange(1, 15)]
    [int]$AttributeNumber,

    [Parameter(Mandatory)]
    [string]$Value,

    [string]$LogRoot = "C:\Logs",

    [switch]$Force
)

#region Write-Log
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Severity = 'INFO'
    )
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Severity] $Message"
    switch ($Severity) {
        'OK'    { Write-Host $line -ForegroundColor Green }
        'WARN'  { Write-Host $line -ForegroundColor Yellow }
        'ERROR' { Write-Host $line -ForegroundColor Red }
        'STEP'  { Write-Host $line -ForegroundColor Cyan }
        default { Write-Host $line }
    }
}
#endregion

if (-not (Test-Path $LogRoot)) { New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null }
$transcriptPath = Join-Path $LogRoot ("SetOUCustomAttribute_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
Start-Transcript -Path $transcriptPath -Append -WhatIf:$false | Out-Null

$attrName = "extensionAttribute$AttributeNumber"

try {
    Write-Log -Severity STEP -Message "Setting $attrName = '$Value' for all users in OU: $OU"

    Import-Module ActiveDirectory -ErrorAction Stop

    $users = Get-ADUser -SearchBase $OU -Filter * -Properties $attrName -ErrorAction Stop
    if (-not $users) {
        Write-Log -Severity WARN -Message "No users found in $OU. Nothing to do."
        Stop-Transcript | Out-Null
        exit 0
    }

    $conflicting = $users | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.$attrName) -and $_.$attrName -ne $Value
    }
    if ($conflicting -and -not $Force) {
        Write-Log -Severity ERROR -Message "$($conflicting.Count) user(s) already have a DIFFERENT value in $attrName (e.g. '$($conflicting[0].$attrName)' on $($conflicting[0].SamAccountName)). Re-run with -Force to overwrite, or pick a different -AttributeNumber."
        Stop-Transcript | Out-Null
        exit 1
    }
    elseif ($conflicting -and $Force) {
        Write-Log -Severity WARN -Message "$($conflicting.Count) user(s) had a different existing value in $attrName — overwriting because -Force was specified."
    }

    Write-Log -Severity INFO -Message "$($users.Count) user(s) in scope."

    if ($PSCmdlet.ShouldProcess("$($users.Count) user(s) in $OU", "Set $attrName = '$Value'")) {
        $successCount = 0
        $failCount    = 0

        foreach ($user in $users) {
            try {
                Set-ADUser -Identity $user.DistinguishedName -Replace @{ $attrName = $Value } -ErrorAction Stop
                Write-Log -Severity OK -Message "Set $attrName on $($user.SamAccountName)"
                $successCount++
            }
            catch {
                Write-Log -Severity ERROR -Message "Failed to set $attrName on $($user.SamAccountName): $($_.Exception.Message)"
                $failCount++
            }
        }

        Write-Log -Severity OK -Message "Complete. $successCount succeeded, $failCount failed."
        Write-Log -Severity INFO -Message "Next: wait for the next Entra Connect delta sync (or run Start-ADSyncSyncCycle -PolicyType Delta on the sync server), then create the dynamic distribution group in Exchange Online."

        if ($failCount -gt 0) {
            Stop-Transcript | Out-Null
            exit 1
        }
    }
}
catch {
    Write-Log -Severity ERROR -Message "Script failed: $($_.Exception.Message)"
    Stop-Transcript | Out-Null
    exit 1
}

Stop-Transcript | Out-Null
exit 0
