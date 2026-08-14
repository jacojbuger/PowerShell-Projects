# Usage
# Basic analysis
# .\Analyze-JNDIAttack.ps1 -LogPath "C:\inetpub\logs\LogFiles"

# Include headers in output
# .\Analyze-JNDIAttack.ps1 -LogPath "C:\inetpub\logs\LogFiles" -IncludeHeaders

# Analyze last 30 days
# .\Analyze-JNDIAttack.ps1 -LogPath "C:\inetpub\logs\LogFiles" -DaysBack 30

# Enhanced IIS Log Analyzer with Additional Detection Rules
param(
    [Parameter(Mandatory=$true)]
    [string]$LogPath,
    
    [Parameter(Mandatory=$false)]
    [int]$DaysBack = 7,
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeHeaders
)

function Test-JNDIInjection {
    param([string]$Content)
    
    $patterns = @(
        'jndi:dns:',
        '\$\{jndi:',
        '%7Bjndi:',
        'jndi:ldap:',
        'jndi:rmi:',
        'jndi:nis:'
    )
    
    foreach ($pattern in $patterns) {
        if ($Content -match $pattern) {
            return $true
        }
    }
    return $false
}

function Test-PayloadPatterns {
    param([string]$URL)
    
    $patterns = @(
        '/\$\{jndi:',
        '/:undefined',
        '/api/',
        '/struts2-showcase/',
        '/JSPWiki/'
    )
    
    foreach ($pattern in $patterns) {
        if ($URL -match $pattern) {
            return $true
        }
    }
    return $false
}

# Main processing
$EndDate = Get-Date
$StartDate = $EndDate.AddDays(-$DaysBack)
$LogFiles = Get-ChildItem -Path $LogPath -Filter "*.log" | 
    Where-Object { $_.LastWriteTime -ge $StartDate }

$results = @()

foreach ($LogFile in $LogFiles) {
    Write-Host "Processing $($LogFile.Name)..."
    
    $entries = Get-Content $LogFile.FullName | 
        Where-Object { $_ -notlike "#*" } |  # Skip comments
        ForEach-Object {
            $parts = $_.Trim() -split '\s+'
            if ($parts.Count -ge 10) {
                [PSCustomObject]@{
                    Date = $parts[0]
                    Time = $parts[1]
                    IP = $parts[2]
                    Method = $parts[3]
                    URL = $parts[4]
                    Status = $parts[5]
                    Bytes = $parts[6]
                    Referrer = $parts[7]
                    UserAgent = $parts[8]
                }
            }
        } | 
        Where-Object { 
            Test-JNDIInjection($_.URL) -or 
            Test-JNDIInjection($_.UserAgent) -or
            Test-PayloadPatterns($_.URL)
        }
    
    $results += $entries
}

# Generate summary
$summary = $results | Group-Object IP | 
    Sort-Object Count -Descending | 
    Select-Object @{Name="IP";Expression={$_.Name}}, 
                  @{Name="Count";Expression={$_.Count}},
                  @{Name="SampleURLs";Expression={
                      ($_.Group | Select-Object -First 3 | ForEach-Object {$_.URL}) -join ", "
                  }}

# Export results
$summary | Export-Csv -Path "$($LogPath)\JNDI_Attack_Summary.csv" -NoTypeInformation
$results | Export-Csv -Path "$($LogPath)\Detailed_JNDI_Attacks.csv" -NoTypeInformation

Write-Host "Analysis complete!"
Write-Host "Summary exported to: $($LogPath)\JNDI_Attack_Summary.csv"
Write-Host "Detailed results exported to: $($LogPath)\Detailed_JNDI_Attacks.csv"
