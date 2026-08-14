# =============================================================================
# Script: Install-HyperVClusterRoles.ps1
# Purpose: Sequentially install Hyper-V and cluster-related roles
# Author: Generated
# =============================================================================

# Define the features to install
$Features = @(
    @{Name="Hyper-V"; IncludeManagement=$true},
    @{Name="RSAT-Hyper-V-Tools"; IncludeManagement=$false},
    @{Name="Failover-Clustering"; IncludeManagement=$false}
)

# Function to install and validate each feature
function Install-FeatureSequential {
    param (
        [string]$FeatureName,
        [bool]$IncludeManagementTools = $false,
        [int]$WaitSeconds = 10
    )

    # Check if already installed
    $feature = Get-WindowsFeature -Name $FeatureName
    if ($feature.Installed) {
        Write-Host "[SKIP] $FeatureName already installed."
        return
    }

    # Install the feature
    Write-Host "[INFO] Installing $FeatureName..."
    if ($IncludeManagementTools) {
        Install-WindowsFeature -Name $FeatureName -IncludeManagementTools -Restart:$false
    } else {
        Install-WindowsFeature -Name $FeatureName -Restart:$false
    }

    # Wait for feature installation to complete
    Write-Host "[INFO] Waiting $WaitSeconds seconds for $FeatureName installation..."
    Start-Sleep -Seconds $WaitSeconds

    # Validate installation
    $feature = Get-WindowsFeature -Name $FeatureName
    if ($feature.Installed) {
        Write-Host "[SUCCESS] $FeatureName installed successfully."
    } else {
        Write-Warning "[FAIL] $FeatureName failed to install. Check logs."
        exit 1
    }
}

# Sequentially install each feature
foreach ($f in $Features) {
    Install-FeatureSequential -FeatureName $f.Name -IncludeManagementTools $f.IncludeManagement
}

Write-Host "[INFO] All features installed successfully. Consider rebooting the host if required."
