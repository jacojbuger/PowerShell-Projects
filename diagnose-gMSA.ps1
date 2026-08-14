#Requires -RunAsAdministrator
<#
.SYNOPSIS
Validates gMSA service account access to SQL Server, DFS namespaces, and UNC paths

.DESCRIPTION
Tests connectivity and permission delegation for Group Managed Service Accounts across
SQL, DFS, and file share resources. Validates gMSA configuration and service account health.

.PARAMETER gMSAName
The name of the Group Managed Service Account (without $ suffix)

.PARAMETER SQLServer
SQL Server instance to test (default: KDC-SQL), change this to your server

.PARAMETER UNCPath
UNC path to test access (default: \\domainname.lab\dfsnamespace)

.PARAMETER Verbose
Provide detailed output for troubleshooting

.EXAMPLE
.\Validate-gMSAAccess.ps1 -gMSAName "MyAppService" -SQLServer "KDC-SQL" -UNCPath "\\domainname.lab\dfsnamespace"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$gMSAName,
    
    [Parameter(Mandatory=$false)]
    [string]$SQLServer = "KDC-SQL",
    
    [Parameter(Mandatory=$false)]
    [string]$UNCPath = "\\domainname.lab\dfsnamespace"
)

# Enable strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Initialize results array
$results = @()

Write-Host "`n=== gMSA Service Account Validation ===" -ForegroundColor Cyan
Write-Host "Testing: $gMSAName" -ForegroundColor Yellow

# ============================================================================
# 1. VALIDATE gMSA EXISTS AND IS HEALTHY
# ============================================================================
Write-Host "`n[1] Validating gMSA Configuration..." -ForegroundColor Green

try {
    # Check if gMSA account exists in AD
    $gMSA = Get-ADServiceAccount -Identity $gMSAName -ErrorAction Stop
    $results += @{
        Test = "gMSA Exists in AD"
        Status = "PASS"
        Details = "SamAccountName: $($gMSA.SamAccountName)"
    }
    
    # Test gMSA credential setup
    $testGMSA = Test-ADServiceAccount -Identity $gMSAName -ErrorAction Stop
    if ($testGMSA) {
        $results += @{
            Test = "gMSA Credential Health"
            Status = "PASS"
            Details = "gMSA can retrieve credentials"
        }
    } else {
        $results += @{
            Test = "gMSA Credential Health"
            Status = "WARN"
            Details = "gMSA may not be configured properly on this host"
        }
    }
    
} catch {
    $results += @{
        Test = "gMSA Configuration"
        Status = "FAIL"
        Details = $_.Exception.Message
    }
    Write-Host "ERROR: gMSA validation failed. Stopping further tests." -ForegroundColor Red
    $results | Format-Table -AutoSize
    exit 1
}

# ============================================================================
# 2. TEST SQL SERVER ACCESS
# ============================================================================
Write-Host "`n[2] Testing SQL Server Access ($SQLServer)..." -ForegroundColor Green

try {
    # Attempt SQL connection
    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection
    $sqlConnection.ConnectionString = "Server=$SQLServer;Integrated Security=true;Connection Timeout=5"
    $sqlConnection.Open()
    
    if ($sqlConnection.State -eq 'Open') {
        $results += @{
            Test = "SQL Server Connectivity"
            Status = "PASS"
            Details = "Connected to $SQLServer (Default Instance)"
        }
        
        # Get server info
        $query = "SELECT @@VERSION as [SQL Version]"
        $cmd = $sqlConnection.CreateCommand()
        $cmd.CommandText = $query
        $version = $cmd.ExecuteScalar()
        
        $results += @{
            Test = "SQL Server Info"
            Status = "INFO"
            Details = $version.Split([Environment]::NewLine)[0]
        }
    }
    $sqlConnection.Close()
    
} catch {
    $results += @{
        Test = "SQL Server Connectivity"
        Status = "FAIL"
        Details = "Cannot connect to $SQLServer - $($_.Exception.Message)"
    }
}

# ============================================================================
# 3. TEST DFS NAMESPACE ACCESS
# ============================================================================
Write-Host "`n[3] Testing DFS Namespace..." -ForegroundColor Green

# Extract DFS namespace from UNC path
$dfsNamespace = $UNCPath -replace '\\\\([^\\]+)\\([^\\]+).*', '\\`1\$2'

try {
    $dfsPath = Get-DfsnFolder -Path $dfsNamespace -ErrorAction Stop
    $results += @{
        Test = "DFS Namespace Resolution"
        Status = "PASS"
        Details = "Namespace exists: $($dfsPath.Path)"
    }
    
    # Get DFS targets
    $dfsTargets = Get-DfsnFolderTarget -Path $dfsNamespace -ErrorAction Stop
    $results += @{
        Test = "DFS Targets Found"
        Status = "PASS"
        Details = "$($dfsTargets.Count) targets found"
    }
    
} catch {
    $results += @{
        Test = "DFS Namespace"
        Status = "WARN"
        Details = "DFS module not available or namespace unavailable - $($_.Exception.Message)"
    }
}

# ============================================================================
# 4. TEST FILE SHARE ACCESS
# ============================================================================
Write-Host "`n[4] Testing File Share Access ($UNCPath)..." -ForegroundColor Green

try {
    # Test basic access
    $testPath = Test-Path -Path $UNCPath -ErrorAction Stop
    
    if ($testPath) {
        $results += @{
            Test = "UNC Path Accessibility"
            Status = "PASS"
            Details = "Path is accessible: $UNCPath"
        }
        
        # List folder contents
        try {
            $folderContents = Get-ChildItem -Path $UNCPath -ErrorAction Stop
            $results += @{
                Test = "Read Permission"
                Status = "PASS"
                Details = "Can enumerate folder ($($folderContents.Count) items found)"
            }
        } catch {
            $results += @{
                Test = "Read Permission"
                Status = "WARN"
                Details = "Cannot enumerate folder contents - $($_.Exception.Message)"
            }
        }
        
        # Test write access
        try {
            $testFile = "$UNCPath\.gMSA-test-$(Get-Random).txt"
            "Test write access" | Out-File -FilePath $testFile -Force -ErrorAction Stop
            Remove-Item -Path $testFile -Force -ErrorAction Stop
            
            $results += @{
                Test = "Write Permission"
                Status = "PASS"
                Details = "Can write to folder"
            }
        } catch {
            $results += @{
                Test = "Write Permission"
                Status = "WARN"
                Details = "Cannot write to folder - $($_.Exception.Message)"
            }
        }
    } else {
        $results += @{
            Test = "UNC Path Accessibility"
            Status = "FAIL"
            Details = "Path not accessible: $UNCPath"
        }
    }
    
} catch {
    $results += @{
        Test = "UNC Path Access"
        Status = "FAIL"
        Details = $_.Exception.Message
    }
}

# ============================================================================
# 5. TEST SUBFOLDERS
# ============================================================================
Write-Host "`n[5] Testing Subfolder Access..." -ForegroundColor Green

try {
    $subFolders = Get-ChildItem -Path $UNCPath -Directory -ErrorAction Stop
    
    foreach ($folder in $subFolders) {
        try {
            $testAccess = Get-ChildItem -Path $folder.FullName -ErrorAction Stop
            $results += @{
                Test = "Subfolder Access: $($folder.Name)"
                Status = "PASS"
                Details = "Readable ($($testAccess.Count) items)"
            }
        } catch {
            $results += @{
                Test = "Subfolder Access: $($folder.Name)"
                Status = "WARN"
                Details = "Not readable - Permission denied"
            }
        }
    }
    
} catch {
    $results += @{
        Test = "Subfolder Enumeration"
        Status = "WARN"
        Details = "Cannot enumerate subfolders - $($_.Exception.Message)"
    }
}

# ============================================================================
# OUTPUT RESULTS
# ============================================================================
Write-Host "`n=== VALIDATION RESULTS ===" -ForegroundColor Cyan

# Display as table
$results | Format-Table -Property @(
    @{Label="Test"; Expression={$_.Test}; Width=35},
    @{Label="Status"; Expression={$_.Status}; Width=10},
    @{Label="Details"; Expression={$_.Details}; Width=50}
) -AutoSize

# Summary
$passCount = ($results | Where-Object {$_.Status -eq "PASS"}).Count
$failCount = ($results | Where-Object {$_.Status -eq "FAIL"}).Count
$warnCount = ($results | Where-Object {$_.Status -eq "WARN"}).Count

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "PASS: $passCount | WARN: $warnCount | FAIL: $failCount" -ForegroundColor Yellow

if ($failCount -gt 0) {
    Write-Host "`n⚠️  CRITICAL: Some access tests failed. Review permissions and gMSA delegation." -ForegroundColor Red
}

Write-Host "`nValidation completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
