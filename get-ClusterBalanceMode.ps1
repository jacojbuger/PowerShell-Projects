<#
Version : 1.0
Purpose : Cluster Resource Movement Audit
Author  : Me

Checks:
- Cluster AutoBalancer settings
- Cluster Groups
- Failback settings
- Preferred Owners
- Current Owners
- Resource states
- Cluster nodes
#>

Clear-Host

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "           FAILOVER CLUSTER MOVEMENT AUDIT"
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

try {
    $Cluster = Get-Cluster -ErrorAction Stop
}
catch {
    Write-Host "Cluster service not detected or cluster unavailable." -ForegroundColor Red
    return
}

# ----------------------------------------------------------
# Cluster Settings
# ----------------------------------------------------------

Write-Host "[ CLUSTER SETTINGS ]" -ForegroundColor Yellow
Write-Host ""

$Cluster |
Select-Object `
    Name,
    AutoBalancerMode,
    AutoBalancerLevel |
Format-List

# ----------------------------------------------------------
# Cluster Nodes
# ----------------------------------------------------------

Write-Host ""
Write-Host "[ CLUSTER NODES ]" -ForegroundColor Yellow
Write-Host ""

Get-ClusterNode |
Sort-Object Name |
Format-Table `
    Name,
    State,
    NodeWeight,
    DynamicWeight -AutoSize

# ----------------------------------------------------------
# Cluster Groups
# ----------------------------------------------------------

Write-Host ""
Write-Host "[ CLUSTER GROUPS ]" -ForegroundColor Yellow
Write-Host ""

Get-ClusterGroup |
Sort-Object Name |
Select-Object `
    Name,
    State,
    OwnerNode,
    FailbackType,
    FailbackWindowStart,
    FailbackWindowEnd |
Format-Table -Wrap -AutoSize

# ----------------------------------------------------------
# Preferred Owners
# ----------------------------------------------------------

Write-Host ""
Write-Host "[ PREFERRED OWNERS ]" -ForegroundColor Yellow
Write-Host ""

foreach ($Group in (Get-ClusterGroup | Sort-Object Name))
{
    Write-Host "Group : $($Group.Name)" -ForegroundColor Cyan

    try {
        $Owners = $Group.OwnerNodes

        if ($Owners) {
            $Owners | ForEach-Object {
                Write-Host "   Preferred Owner : $($_.Name)"
            }
        }
        else {
            Write-Host "   Preferred Owner : Not Configured" -ForegroundColor DarkYellow
        }
    }
    catch {
        Write-Host "   Unable to determine preferred owners." -ForegroundColor Red
    }

    Write-Host ""
}

# ----------------------------------------------------------
# Resources
# ----------------------------------------------------------

Write-Host ""
Write-Host "[ CLUSTER RESOURCES ]" -ForegroundColor Yellow
Write-Host ""

Get-ClusterResource |
Sort-Object OwnerGroup, Name |
Select-Object `
    Name,
    ResourceType,
    State,
    OwnerGroup |
Format-Table -Wrap -AutoSize

# ----------------------------------------------------------
# Potential Issues
# ----------------------------------------------------------

Write-Host ""
Write-Host "[ MOVEMENT ANALYSIS ]" -ForegroundColor Yellow
Write-Host ""

if ($Cluster.AutoBalancerMode -eq 0)
{
    Write-Host "[OK] AutoBalancer is DISABLED." -ForegroundColor Green
}
else
{
    Write-Host "[WARN] AutoBalancer is ENABLED (Mode $($Cluster.AutoBalancerMode))." -ForegroundColor Yellow
}

$GroupsWithFailback = Get-ClusterGroup |
Where-Object {
    $_.FailbackType -ne "PreventFailback"
}

if ($GroupsWithFailback)
{
    Write-Host ""
    Write-Host "[WARN] Groups allowing automatic failback:" -ForegroundColor Yellow

    $GroupsWithFailback |
    Select-Object Name, FailbackType |
    Format-Table -AutoSize
}
else
{
    Write-Host "[OK] No groups allow automatic failback." -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Audit Complete"
Write-Host "==========================================================" -ForegroundColor Cyan
