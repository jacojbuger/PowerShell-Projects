log4shell-basic-scrape.ps1
# IIS Log Analysis for JNDI Injection Attacks
# Usage: .\Analyze-JNDIAttack.ps1 -LogPath "C:\inetpub\logs\LogFiles"

param(
    [Parameter(Mandatory=$true)]
    [string]$LogPath,
    
    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 7
)

# Get relevant log files from last N days
$EndDate = Get-Date
$StartDate = $EndDate.AddDays(-$DaysBack)
$LogFiles = Get-ChildItem -Path $LogPath -Filter "*.log" | 
    Where-Object { $_.LastWriteTime -ge $StartDate }

# Process each log file
foreach ($LogFile in $LogFiles) {
    Write-Host "Processing $($LogFile.Name)..."
    
    # Extract relevant entries
    $Entries = Get-Content $LogFile.FullName | 
        Select-String 'jndi:dns:' |
        ForEach-Object {
            $line = $_.Line
            # Parse IIS log fields (adjust based on your log format)
            $fields = $line -split '\s+'
            
            # Extract key fields
            [PSCustomObject]@{
                Timestamp = $fields[0]
                IP = $fields[2]
                Method = $fields[3]
                URL = $fields[4]
                Status = $fields[5]
                Bytes = $fields[6]
                UserAgent = $fields[7]
            }
        }
    
    # Output results
    if ($Entries.Count -gt 0) {
        $FileName = $LogFile.Name -replace '\.log$', '.csv'
        $Entries | Export-Csv -Path "$($LogFile.Directory)\$FileName" -NoTypeInformation
        
        Write-Host "Found $($Entries.Count) potential JNDI injection attempts in $($LogFile.Name)"
        $Entries | Format-Table -AutoSize
    }
}

Write-Host "Analysis complete. Results saved to CSV files."
