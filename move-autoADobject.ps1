# ======================
# AD-AutoMoveAndLog.ps1
# ======================
param (
    [string] $SourceContainer = "CN=Computers,DC=domainname,DC=lab",
    [string] $ServerOU        = "OU=domain servers,DC=domainname,DC=lab",
    [string] $ClientOU        = "OU=domain computers,DC=domainname,DC=lab",
    [string] $LinuxOU         = "OU=domain enabled linux,DC=domainname,DC=lab",
    [string] $NameFilter      = "KDC"
)

Import-Module ActiveDirectory

# Event Log config
$EventLogName = "Application"
$EventSource  = "AD-AutoMoveScript"

if (-not [System.Diagnostics.EventLog]::SourceExists($EventSource)) {
    try {
        New-EventLog -LogName $EventLogName -Source $EventSource
    }
    catch {}
}

# Capture caller context
$joiningUser = $env:USERNAME
$joiningHost = $env:COMPUTERNAME
$timestamp   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Counters
[int] $MovedServerCount = 0
[int] $MovedClientCount = 0
[int] $MovedLinuxCount  = 0
[int] $SkippedNameCount = 0
[int] $UnknownOSCount   = 0

# Fetch computer objects
$newComputers = Get-ADComputer -Filter * -SearchBase $SourceContainer -Property OperatingSystem, Name, DistinguishedName

foreach ($computer in $newComputers) {
    $os           = $computer.OperatingSystem
    $computerName = $computer.Name

    if ($computerName -like "*$NameFilter*") {

        # Metadata for description
        $desc = "Joined by user: $joiningUser; Joined from host: $joiningHost; Date: $timestamp"

        if ($os -like "Windows Server*") {
            Move-ADObject -Identity $computer.DistinguishedName -TargetPath $ServerOU -ErrorAction Stop
            Set-ADComputer -Identity $computer.DistinguishedName -Description $desc -ErrorAction Stop
            $MovedServerCount++
            Write-Host "Moved Server $computerName → $ServerOU"

        } elseif ($os -like "Windows 11*" -or $os -like "Windows 10*") {
            Move-ADObject -Identity $computer.DistinguishedName -TargetPath $ClientOU -ErrorAction Stop
            Set-ADComputer -Identity $computer.DistinguishedName -Description $desc -ErrorAction Stop
            $MovedClientCount++
            Write-Host "Moved Client $computerName → $ClientOU"

        } elseif ($os -like "Linux*") {
            Move-ADObject -Identity $computer.DistinguishedName -TargetPath $LinuxOU -ErrorAction Stop
            Set-ADComputer -Identity $computer.DistinguishedName -Description $desc -ErrorAction Stop
            $MovedLinuxCount++
            Write-Host "Moved Linux host $computerName → $LinuxOU"

        } else {
            $UnknownOSCount++
            Write-Host "Unknown OS '$os' for $computerName — left in source container"
        }

    } else {
        $SkippedNameCount++
        Write-Host "Name filter did not match $computerName — left in source container"
    }
}

# ============================
# EVENT LOG CONTROL – ONLY IF MOVES OCCURRED
# ============================

$totalMoves = $MovedServerCount + $MovedClientCount + $MovedLinuxCount

if ($totalMoves -gt 0) {

    $eventMessage = @"
AD Auto-Move Script executed.
Summary:
  Moved Servers: $MovedServerCount
  Moved Clients: $MovedClientCount
  Moved Linux:   $MovedLinuxCount
  Skipped (Name filter): $SkippedNameCount
  Unknown OS: $UnknownOSCount
Joined by: $joiningUser
Run on host: $joiningHost
Execution time: $timestamp
"@

    try {
        Write-EventLog -LogName $EventLogName -Source $EventSource -EntryType Information -EventId 11001 -Message $eventMessage
    }
    catch {}
    
    Write-Host "Changes detected — event log entry written."
}
else {
    Write-Host "No AD object moves performed — no event log entry created."
}
