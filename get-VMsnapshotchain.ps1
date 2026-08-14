# Run as Administrator on Hyper-V host

$VMs = Get-VM

Write-Host "=== Hyper-V Snapshot Chain Validation & Merge Script ===" -ForegroundColor Cyan

foreach ($vm in $VMs) {
    Write-Host "`nVM: $($vm.Name)" -ForegroundColor Yellow
    
    $snapshots = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue
    
    if ($snapshots) {
        Write-Host "  Snapshots found: $($snapshots.Count)" -ForegroundColor Magenta
        
        foreach ($snap in $snapshots) {
            Write-Host "    Snapshot: $($snap.Name) | Created: $($snap.CreationTime)"
        }

        # Inspect virtual disks
        $disks = Get-VMHardDiskDrive -VMName $vm.Name

        foreach ($disk in $disks) {
            $vhd = Get-VHD -Path $disk.Path -ErrorAction SilentlyContinue
            
            if ($vhd) {
                Write-Host "  Disk: $($vhd.Path)" -ForegroundColor Cyan
                
                # Walk the parent chain
                $current = $vhd
                $chain = @()

                while ($current.ParentPath) {
                    $chain += $current.Path
                    try {
                        $current = Get-VHD -Path $current.ParentPath -ErrorAction Stop
                    }
                    catch {
                        Write-Host "    ⚠ Corruption detected: Cannot access parent $($current.ParentPath)" -ForegroundColor Red
                        break
                    }
                }

                $chain += $current.Path

                Write-Host "    Chain length: $($chain.Count)"

                # Check for orphaned AVHDX
                foreach ($file in $chain) {
                    if (-not (Test-Path $file)) {
                        Write-Host "    ⚠ Missing file in chain: $file" -ForegroundColor Red
                    }
                }
            }
        }

        # Attempt merge (only on OFF VMs)
        if ($vm.State -eq "Off") {
            Write-Host "  VM is OFF - attempting merge of checkpoints..." -ForegroundColor Green
            
            try {
                Get-VMSnapshot -VMName $vm.Name | Remove-VMSnapshot -Confirm:$false
                Write-Host "  ✅ Merge initiated (snapshots deleted)" -ForegroundColor Green
            }
            catch {
                Write-Host "  ⚠ Merge failed: $_" -ForegroundColor Red
            }
        }
        else {
            Write-Host "  VM is running - skipping merge (safe practice)" -ForegroundColor DarkYellow
        }
    }
    else {
        Write-Host "  No snapshots found." -ForegroundColor Green
    }
}

Write-Host "`n=== Script Completed ===" -ForegroundColor Cyan
