<#
.VERSION
    2.0

.DESCRIPTION
    Enables built-in firewall rules required for remote management
    (WinRM + minimal RPC) using idempotent logic.

    - Validates rule existence before acting
    - Skips already enabled rules
    - Uses only built-in rules (no custom rules created)

.NOTES
    Compatible: PowerShell 5.x
#>

#region Config
$ErrorActionPreference = "Stop"

# Focus only on relevant built-in rule groups
$TargetGroups = @(
    "Windows Remote Management",
    "Remote Service Management",
    "Remote Event Log Management"
)

#endregion

#region Logging
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "[$ts] [$Level] $Message"
}
#endregion

#region Core Function

function Enable-FirewallGroupSafe {
    param (
        [Parameter(Mandatory)]
        [string]$GroupName
    )

    try {
        # Check existence
        $rules = Get-NetFirewallRule -DisplayGroup $GroupName -ErrorAction SilentlyContinue

        if (-not $rules) {
            Write-Log "Group '$GroupName' does not exist on this system" "WARN"
            return
        }

        # Split enabled vs disabled
        $enabled = $rules | Where-Object { $_.Enabled -eq "True" }
        $disabled = $rules | Where-Object { $_.Enabled -eq "False" }

        # Report state
        Write-Log "Group '$GroupName' -> Total: $($rules.Count), Enabled: $($enabled.Count), Disabled: $($disabled.Count)"

        # Enable only if needed
        if ($disabled.Count -gt 0) {
            $disabled | Enable-NetFirewallRule -ErrorAction Stop
            Write-Log "Enabled $($disabled.Count) rule(s) in group '$GroupName'"
        }
        else {
            Write-Log "No action required for '$GroupName'"
        }
    }
    catch {
        Write-Log "Error processing group '$GroupName' - $_" "ERROR"
    }
}

#endregion

#region Validation

function Test-WinRM {
    try {
        Test-WSMan -ErrorAction Stop | Out-Null
        Write-Log "WinRM connectivity test successful"
    }
    catch {
        Write-Log "WinRM test failed - $_" "ERROR"
    }
}

function Test-RPCPort135 {
    try {
        $rpcRules = Get-NetFirewallRule |
            Where-Object {
                ($_ | Get-NetFirewallPortFilter).LocalPort -eq 135
            }

        if ($rpcRules) {
            $enabled = $rpcRules | Where-Object { $_.Enabled -eq "True" }
            Write-Log "RPC Port 135 rules found: $($rpcRules.Count), Enabled: $($enabled.Count)"
        }
        else {
            Write-Log "No RPC (135) rules found" "WARN"
        }
    }
    catch {
        Write-Log "RPC validation failed - $_" "ERROR"
    }
}

#endregion

#region Execution

Write-Log "Starting remote management firewall configuration (v2.0)"

foreach ($group in $TargetGroups) {
    Enable-FirewallGroupSafe -GroupName $group
}

# Validation phase
Write-Log "Running validation checks"

Test-WinRM
Test-RPCPort135

Write-Log "Completed firewall configuration"

#endregion
