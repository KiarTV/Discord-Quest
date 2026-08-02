# ---------------------------------------------------------------------------
# Mirror queue - only one mirror runs at a time; anything requested while
# one is active goes into $script:MirrorQueue and auto-starts once the
# active mirror exits. Cross-platform: relies only on Get-Process/Path and
# the Deploy-Stub/Start-Mirror dispatchers from PlatformDispatch.ps1.
# ---------------------------------------------------------------------------

function Get-ActiveMirrorProcesses {
    return Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($script:MirrorsDir, [StringComparison]::OrdinalIgnoreCase) }
}

function Get-ActiveMirrorInfo {
    Get-ActiveMirrorProcesses | ForEach-Object {
        $exeName = Split-Path $_.Path -Leaf
        $displayName = $script:MirrorNameMap[$exeName]
        if (-not $displayName) { $displayName = $exeName }
        [PSCustomObject]@{ Process = $_; ExeName = $exeName; DisplayName = $displayName }
    }
}

function Test-MirrorActive {
    return [bool](Get-ActiveMirrorProcesses)
}

function Stop-Mirror {
    param([string]$Query)

    $active = @(Get-ActiveMirrorInfo)
    $matched = @($active | Where-Object { $_.DisplayName -eq $Query -or $_.ExeName -eq $Query })
    if ($matched.Count -eq 0) {
        $matched = @($active | Where-Object { $_.DisplayName -like "*$Query*" -or $_.ExeName -like "*$Query*" })
    }

    if ($matched.Count -eq 0) {
        Write-Warn2 "No running mirror matching '$Query' found"
        return
    }
    foreach ($m in $matched) {
        Stop-Process -Id $m.Process.Id -Force
        Write-Ok "Stopped $($m.DisplayName) (PID $($m.Process.Id))"
    }
}

function Stop-AllMirrors {
    $active = @(Get-ActiveMirrorInfo)
    if ($active.Count -eq 0) {
        Write-Warn2 "No active mirrors to stop"
        return
    }
    foreach ($m in $active) {
        Stop-Process -Id $m.Process.Id -Force
        Write-Ok "Stopped $($m.DisplayName) (PID $($m.Process.Id))"
    }
}

function Show-ActiveMirrors {
    $active = @(Get-ActiveMirrorInfo)
    if ($active.Count -eq 0) {
        Write-Meta "No active mirrors."
    } else {
        Write-Host ""
        Write-Host ("  {0,-28} {1,-8} {2}" -f 'GAME', 'PID', 'EXPIRES') -ForegroundColor DarkGray
        foreach ($m in $active) {
            $expires = $m.Process.StartTime.AddSeconds($MirrorDurationSeconds).ToString('HH:mm:ss')
            Write-Host ("  {0,-28} {1,-8} {2}" -f $m.DisplayName, $m.Process.Id, $expires) -ForegroundColor White
        }
        Write-Host ""
    }

    if ($script:MirrorQueue.Count -gt 0) {
        Write-Host "  Queued:" -ForegroundColor DarkGray
        $i = 1
        foreach ($item in $script:MirrorQueue.ToArray()) {
            Write-Host ("      [{0}] {1}" -f $i, $item.DisplayName) -ForegroundColor Gray
            $i++
        }
        Write-Host ""
    }
}

function Invoke-QueuePump {
    if ($script:MirrorQueue.Count -eq 0 -or (Test-MirrorActive)) { return }

    $next = $script:MirrorQueue.Dequeue()
    Write-Host ""
    Write-Step "Starting queued mirror: $($next.DisplayName)"
    Start-MirrorForGame -ExeName $next.ExeName -DisplayName $next.DisplayName
}

function Get-StopCandidates {
    param([string]$Typed)

    $names = @((Get-ActiveMirrorInfo | ForEach-Object { $_.DisplayName }) + 'all') | Select-Object -Unique
    return @($names | Where-Object { $_.ToLowerInvariant().StartsWith($Typed.ToLowerInvariant()) })
}

function Start-MirrorForGame {
    param([string]$ExeName, [string]$DisplayName)

    $script:MirrorNameMap[$ExeName] = $DisplayName

    $target = Deploy-Stub -ExeName $ExeName
    $proc = Start-Mirror -ExePath $target

    if ($proc.Alive) {
        $expires = (Get-Date).AddSeconds($MirrorDurationSeconds).ToString('HH:mm:ss')
        Write-Ok "Mirror running - PID $($proc.Id), expires ~$expires"
        Write-Meta "Stop early with: /stop $DisplayName"
    }
}
