# iSCSI and MPIO Health Check Script for Windows Server 2022 Core
# Run as Administrator

param(
    [string]$LogPath = "C:\Logs\iSCSI_MPIO_HealthCheck.log"
)

# Create log directory if it doesn't exist
$logDir = Split-Path $LogPath
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $logMessage
    
    Write-Host $logMessage -ForegroundColor $(
        switch ($Level) {
            "Error" { "Red" }
            "Warning" { "Yellow" }
            default { "Green" }
        }
    )
}

Write-Log "======== Starting iSCSI and MPIO Health Check ========"

# Check if running as Administrator
$admin = [Security.Principal.WindowsIdentity]::GetCurrent() | ForEach-Object {
    [Security.Principal.WindowsPrincipal]::new($_).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $admin) {
    Write-Log "Script must be run as Administrator" "Error"
    exit 1
}

Write-Log "Running as Administrator: Confirmed"

# ==================== iSCSI Health Checks ====================
Write-Log "--- iSCSI Health Checks ---"

try {
    $iscsiService = Get-Service -Name "msiscsi" -ErrorAction Stop
    Write-Log "iSCSI Service Status: $($iscsiService.Status)"
    
    if ($iscsiService.Status -ne "Running") {
        Write-Log "iSCSI Service is not running" "Warning"
    }
    
    # Get iSCSI initiator ports
    Write-Log "Checking iSCSI Initiator Ports..."
    try {
        $initiatorPorts = Get-InitiatorPort -ErrorAction SilentlyContinue
        if ($initiatorPorts) {
            Write-Log "iSCSI Initiator Ports: $($initiatorPorts.Count)"
            foreach ($port in $initiatorPorts) {
                Write-Log "  - NodeAddress: $($port.NodeAddress) | PortAddress: $($port.PortAddress)"
            }
        } else {
            Write-Log "No iSCSI initiator ports configured" "Warning"
        }
    } catch {
        Write-Log "Could not query initiator ports: $($_.Exception.Message)" "Warning"
    }
    
    # Detect Active iSCSI Sessions
    Write-Log "Checking for Active iSCSI Sessions..."
    try {
        $sessions = Get-IscsiSession -ErrorAction SilentlyContinue
        if ($sessions) {
            Write-Log "Active iSCSI Sessions: $($sessions.Count)"
            foreach ($session in $sessions) {
                $sessionState = if ($session.IsConnected) { "Connected" } else { "Disconnected" }
                Write-Log "  - Target: $($session.TargetNodeAddress) | Status: $sessionState"
            }
        } else {
            Write-Log "No active iSCSI sessions detected" "Warning"
        }
    } catch {
        Write-Log "Could not query iSCSI sessions: $($_.Exception.Message)" "Warning"
    }
    
    # iSCSI Network Adapters
    $iscsiAdapters = Get-NetAdapter | Where-Object { $_.Name -match "iSCSI" }
    Write-Log "iSCSI Network Adapters Found: $($iscsiAdapters.Count)"
    
    foreach ($adapter in $iscsiAdapters) {
        Write-Log "  - Adapter: $($adapter.Name) | Status: $($adapter.Status) | Speed: $($adapter.LinkSpeed)"
    }
    
    # Network/iSCSI Disks
    $allDisks = Get-Disk
    $networkDisks = $allDisks | Where-Object { $_.BusType -eq "iSCSI" -or $_.BusType -match "RAID" }
    
    if ($networkDisks) {
        Write-Log "Network/iSCSI Disks: $($networkDisks.Count)"
        foreach ($disk in $networkDisks) {
            $sizeGB = [math]::Round($disk.Size / 1GB, 2)
            Write-Log "  - Disk: $($disk.Number) | BusType: $($disk.BusType) | Size: $sizeGB GB | Status: $($disk.OperationalStatus)"
        }
    } else {
        Write-Log "Network/iSCSI Disks: 0"
    }
    
} catch {
    Write-Log "Error retrieving iSCSI information: $($_.Exception.Message)" "Error"
}

# ==================== MPIO Health Checks ====================
Write-Log "--- MPIO Health Checks ---"

try {
    $mpioService = Get-Service -Name "msdsm" -ErrorAction SilentlyContinue
    
    if ($mpioService) {
        Write-Log "MPIO Service Status: $($mpioService.Status)"
        
        if ($mpioService.Status -ne "Running") {
            Write-Log "MPIO Service is not running" "Warning"
        } else {
            # MPIO-capable Disks
            Write-Log "Checking for MPIO-enabled disks..."
            $disks = Get-Disk
            $mpioDisks = @()
            
            foreach ($disk in $disks) {
                if ($disk.BusType -match "RAID|SAS|iSCSI|NVMe") {
                    $mpioDisks += $disk
                }
            }
            
            if ($mpioDisks.Count -gt 0) {
                Write-Log "MPIO-capable Disks: $($mpioDisks.Count)"
                foreach ($disk in $mpioDisks) {
                    $sizeGB = [math]::Round($disk.Size / 1GB, 2)
                    Write-Log "  - Disk $($disk.Number): $sizeGB GB | Bus: $($disk.BusType) | Status: $($disk.OperationalStatus)"
                }
            } else {
                Write-Log "MPIO-capable Disks: 0" "Warning"
            }
            
            # Detect True MPIO Paths using mpclaim
            Write-Log "Querying MPIO device paths..."
            try {
                $mpioClaim = cmd /c "mpclaim.exe -s -d" 2>&1
                
                if ($mpioClaim -and $mpioClaim.Count -gt 0) {
                    Write-Log "MPIO Device Summary:"
                    foreach ($line in $mpioClaim) {
                        $trimmedLine = [string]$line
                        if ($trimmedLine.Trim()) {
                            Write-Log "  $trimmedLine"
                        }
                    }
                } else {
                    Write-Log "No MPIO devices detected via mpclaim" "Warning"
                }
            } catch {
                Write-Log "Could not query MPIO paths via mpclaim: $($_.Exception.Message)" "Warning"
            }
            
            # RAID configuration via diskraid
            Write-Log "Querying RAID configuration via diskraid..."
            $diskraidOutput = cmd /c "diskraid" 2>&1
            
            $raidLines = $diskraidOutput | Where-Object { $_ -match "Subsystem|Status" }
            if ($raidLines) {
                foreach ($line in $raidLines) {
                    Write-Log "  $line"
                }
            }
        }
    } else {
        Write-Log "MPIO Service not installed" "Warning"
    }
    
} catch {
    Write-Log "Error retrieving MPIO information: $($_.Exception.Message)" "Error"
}

# ==================== Storage Health ====================
Write-Log "--- Storage Health Checks ---"

try {
    Write-Log "Physical Disk Summary:"
    $disks = Get-PhysicalDisk
    Write-Log "Total Physical Disks: $($disks.Count)"
    
    $healthyCount = ($disks | Where-Object { $_.HealthStatus -eq "Healthy" }).Count
    $unhealthyCount = ($disks | Where-Object { $_.HealthStatus -ne "Healthy" }).Count
    
    Write-Log "  Healthy: $healthyCount | Unhealthy: $unhealthyCount"
    
    foreach ($disk in $disks) {
        $sizeGB = [math]::Round($disk.Size / 1GB, 2)
        if ($disk.HealthStatus -ne "Healthy") {
            Write-Log "  ALERT: $($disk.FriendlyName) | Health: $($disk.HealthStatus) | Size: $($sizeGB) GB | Status: $($disk.OperationalStatus)" "Warning"
        } else {
            Write-Log "  OK: $($disk.FriendlyName) | Size: $($sizeGB) GB"
        }
    }
    
} catch {
    Write-Log "Error retrieving storage information: $($_.Exception.Message)" "Error"
}

# ==================== Network Interface Check ====================
Write-Log "--- Network Interface Checks ---"

try {
    Write-Log "Network Adapter Summary:"
    $adapters = Get-NetAdapter
    $upAdapters = $adapters | Where-Object { $_.Status -eq "Up" }
    $downAdapters = $adapters | Where-Object { $_.Status -ne "Up" }
    
    Write-Log "Total Adapters: $($adapters.Count) | Up: $($upAdapters.Count) | Down: $($downAdapters.Count)"
    
    if ($upAdapters) {
        Write-Log "Active Adapters:"
        foreach ($adapter in $upAdapters) {
            Write-Log "  OK: $($adapter.Name) | Speed: $($adapter.LinkSpeed) | MTU: $($adapter.MtuSize)"
        }
    }
    
    if ($downAdapters) {
        Write-Log "Inactive Adapters:" "Warning"
        foreach ($adapter in $downAdapters) {
            Write-Log "  ALERT: $($adapter.Name) | Status: $($adapter.Status)" "Warning"
        }
    }
    
} catch {
    Write-Log "Error retrieving network information: $($_.Exception.Message)" "Error"
}

Write-Log "======== Health Check Complete ========"
Write-Log "Log saved to: $LogPath"

# Return exit code based on health
$errors = @(Get-Content $LogPath | Where-Object { $_ -match "\[Error\]|\[Warning\]" })
exit $(if ($errors.Count -gt 0) { 1 } else { 0 })
