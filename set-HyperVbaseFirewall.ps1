#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Hyper-V Cluster Host - Firewall Baseline (Domain Profile Only)
    Windows Server 2025 Core

.DESCRIPTION
    Enables built-in Windows Firewall rule groups on the Domain profile only.
    Checks existence and current state before applying.
    Designed for physical Hyper-V hosts in a Microsoft Failover Cluster.

    Includes prerequisite rules for:
      - Kerberos authentication (DNS, LDAP, AD DS, Netlogon)
      - Secure Channel (Netlogon RPC, DFS-R SYSVOL health)
      - SMB Signing transport (TCP 445 via File and Printer Sharing)

    NOTE: SMB Signing and Kerberos enforcement must be applied separately via GPO.

.NOTES
    Run on each cluster node individually or via Invoke-Command.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =============================================================================
# CONFIGURATION
# =============================================================================
$TargetProfile = 'Domain'

$RuleGroups = @(
    # Remote Management
    'Windows Management Instrumentation (WMI)',
    'COM+ Network Access (DCOM-In)',
    'Remote Registry',
    'Remote Event Log Management',
    'Remote Service Management',
    'Remote Scheduled Tasks Management',
    'Performance Logs and Alerts',
    'Remote Volume Management',

    # Windows Remote Management
    'Windows Remote Management',
    'Windows Remote Management - Compatibility Mode',
    'Remote Administration',

    # Hyper-V
    'Hyper-V',
    'Hyper-V - Live Migration',
    'Hyper-V Replica HTTP',
    'Hyper-V Replica HTTPS',
    'Hyper-V Management Clients',

    # Failover Clustering
    'Failover Clustering',
    'Failover Cluster Manager',

    # File and Printer Sharing
    'File and Printer Sharing',

    # Kerberos / Secure Channel / SMB Signing prerequisites
    'Netlogon Service',
    'Active Directory Domain Services',
    'DNS Client',
    'DFS Replication',

    # Already configured - checks only
    'Remote Desktop',
    'Network Discovery'
)

# =============================================================================
# FUNCTION: Check and enable a firewall display group
# =============================================================================
function Invoke-FirewallGroupCheck {
    param (
        [string]$Group,
        [string]$Profile
    )

    # Skip groups based on roles not installed
    $roleMapping = @{
        'Hyper-V'                = 'Hyper-V'
        'Hyper-V - Live Migration' = 'Hyper-V'
        'Hyper-V Replica HTTP'     = 'Hyper-V'
        'Hyper-V Replica HTTPS'    = 'Hyper-V'
        'Hyper-V Management Clients' = 'Hyper-V'
        'Failover Clustering'        = 'Failover-Clustering'
        'Failover Cluster Manager'   = 'Failover-Clustering'
    }

    if ($roleMapping.ContainsKey($Group)) {
        $role = $roleMapping[$Group]
        if (-not (Get-WindowsFeature -Name $role).Installed) {
            Write-Host "  [SKIP] $Group - role $role not installed." -ForegroundColor Yellow
            return [PSCustomObject]@{ Group=$Group; Status='Skipped'; Action="Role $role not installed" }
        }
    }

    $rules = Get-NetFirewallRule -DisplayGroup $Group -ErrorAction SilentlyContinue
    if (-not $rules) {
        Write-Warning "  [NOT FOUND] '$Group' - no built-in rules found on this OS. Skipping."
        return [PSCustomObject]@{ Group=$Group; Status='NotFound'; Action='None' }
    }

    # Filter inbound rules for target profile
    $inboundRules = @($rules | Where-Object { $_.Direction -eq 'Inbound' -and ($_.Profile -match $Profile -or $_.Profile -eq 'Any') })
    if (-not $inboundRules) {
        Write-Warning "  [NO INBOUND] '$Group' - no rules match Inbound + $Profile profile."
        return [PSCustomObject]@{ Group=$Group; Status='NoMatchingInbound'; Action='None' }
    }

    # Ensure always arrays
    $disabled = @($inboundRules | Where-Object { $_.Enabled -eq 'False' })
    $enabled  = @($inboundRules | Where-Object { $_.Enabled -eq 'True' })

    $disabledCount = if ($disabled) { $disabled.Count } else { 0 }
    $enabledCount  = if ($enabled)  { $enabled.Count }  else { 0 }

    if ($disabledCount -eq 0) {
        Write-Host "  [OK]   '$Group' - all $enabledCount inbound rule(s) already enabled." -ForegroundColor Green
        return [PSCustomObject]@{ Group=$Group; Status='AlreadyEnabled'; Action='None' }
    }

    Write-Host "  [ENABLING] '$Group' - $disabledCount disabled, $enabledCount already enabled." -ForegroundColor Cyan
    foreach ($rule in $disabled) {
        try { Set-NetFirewallRule -Name $rule.Name -Enabled True -Profile $Profile }
        catch { Write-Warning "    ! Failed '$($rule.DisplayName)': $_" }
    }

    return [PSCustomObject]@{ Group=$Group; Status='Updated'; Action="Enabled $disabledCount rule(s)" }
}

# =============================================================================
# FUNCTION: ICMP (Ping) - individual rule names
# =============================================================================
function Invoke-IcmpCheck {
    param([string]$Profile)

    $icmpRules = @(
        'Core Networking Diagnostics - ICMP Echo Request (ICMPv4-In)',
        'Core Networking Diagnostics - ICMP Echo Request (ICMPv6-In)'
    )

    foreach ($ruleName in $icmpRules) {
        $rule = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
        if (-not $rule) {
            Write-Warning "  [NOT FOUND] ICMP rule '$ruleName' not found."
            continue
        }

        $enabled = $rule.Enabled -eq 'True'
        if ($enabled) {
            Write-Host "  [OK]      ICMP '$($rule.DisplayName)' already enabled." -ForegroundColor Green
        } else {
            Set-NetFirewallRule -Name $ruleName -Enabled True -Profile $Profile
            Write-Host "  [ENABLED] ICMP '$($rule.DisplayName)'" -ForegroundColor Cyan
        }
    }
}

# =============================================================================
# MAIN
# =============================================================================
Write-Host ""
Write-Host "=========================================================" -ForegroundColor Yellow
Write-Host " Hyper-V Host Firewall Baseline - Domain Profile Only" -ForegroundColor Yellow
Write-Host " Host : $($env:COMPUTERNAME)" -ForegroundColor Yellow
Write-Host " Time : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Yellow
Write-Host ""

# Warn if no domain profile active
$domainAdapters = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'DomainAuthenticated' }
if (-not $domainAdapters) {
    Write-Warning "No adapters are currently authenticated to the Domain profile."
    Write-Warning "Rules will be staged but inactive until domain authentication."
    Write-Host ""
}

# ICMP
Write-Host "[ ICMP / Ping ]" -ForegroundColor Magenta
Invoke-IcmpCheck -Profile $TargetProfile
Write-Host ""

# Rule groups
$Results = [System.Collections.Generic.List[PSCustomObject]]::new()
foreach ($group in $RuleGroups) {
    Write-Host "[ $group ]" -ForegroundColor Magenta
    $result = Invoke-FirewallGroupCheck -Group $group -Profile $TargetProfile
    $Results.Add($result)
    Write-Host ""
}

# Summary
Write-Host "=========================================================" -ForegroundColor Yellow
Write-Host " SUMMARY" -ForegroundColor Yellow
Write-Host "=========================================================" -ForegroundColor Yellow
Write-Host ""

$Results | Format-Table -AutoSize -Property @(
    @{ Label = 'Group';  Expression = { $_.Group }; Width = 55 },
    @{ Label = 'Status'; Expression = { $_.Status }; Width = 20 },
    @{ Label = 'Action'; Expression = { $_.Action }; Width = 25 }
)

$skipped  = @($Results | Where-Object { $_.Status -eq 'Skipped' })
$notFound = @($Results | Where-Object { $_.Status -eq 'NotFound' })
$updated  = @($Results | Where-Object { $_.Status -eq 'Updated' })
$already  = @($Results | Where-Object { $_.Status -eq 'AlreadyEnabled' })

Write-Host "Groups enabled  : $($updated.Count)" -ForegroundColor Cyan
Write-Host "Already correct : $($already.Count)" -ForegroundColor Green
Write-Host "Skipped         : $($skipped.Count)" -ForegroundColor Yellow
Write-Host "Not found       : $($notFound.Count)" -ForegroundColor $(if ($notFound.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host ""
Write-Host "Baseline complete. Lockdown pass is a separate phase." -ForegroundColor Yellow
Write-Host ""
