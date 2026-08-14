# List tasks with useful summary info (no event log)
# Tip: Run as Administrator to avoid access errors for some tasks.

Get-ScheduledTask |
    Where-Object { $_.TaskPath -notlike '\Microsoft\Windows\*' } |  # optional filter
    ForEach-Object {
        $info = $null
        try {
            $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath
        } catch {
            # Swallow and continue; $info stays $null for this task
        }

        # Normalize LastRunTime/NextRunTime: replace [datetime]::MinValue with $null (or 'Never')
        $lastRun = $null
        if ($info -and $info.LastRunTime -ne [datetime]::MinValue) {
            $lastRun = $info.LastRunTime
        }

        $nextRun = $null
        if ($info -and $info.NextRunTime -ne [datetime]::MinValue) {
            $nextRun = $info.NextRunTime
        }

        $lastResult = $null
        if ($info) { $lastResult = $info.LastTaskResult }

        $missed = $null
        if ($info) { $missed = $info.NumberOfMissedRuns }

        [pscustomobject]@{
            TaskPath       = $_.TaskPath
            TaskName       = $_.TaskName
            State          = $_.State
            LastRunTime    = $lastRun      # shows blank if never run; or change to: ($lastRun ?? 'Never')
            NextRunTime    = $nextRun
            LastTaskResult = $lastResult
            MissedRuns     = $missed
        }
    } |
    Sort-Object TaskPath, TaskName |
    Format-Table -AutoSize
