# ---------------------------------------------------------------------------
# Driver - REPL/non-interactive entry point. Everything above this has only
# defined functions; this is the first place anything actually runs.
# ---------------------------------------------------------------------------

function Show-Help {
    Write-Host ""
    Write-Host "  Commands" -ForegroundColor DarkCyan
    Write-Host "    <game name>       start a mirror, or queue it if one's already running" -ForegroundColor Gray
    Write-Host "    <game name> --pick   choose which executable to use, if the first didn't work" -ForegroundColor Gray
    Write-Host "    /status           show the running mirror and the queue" -ForegroundColor Gray
    Write-Host "    /stop <game name> stop it if running, or cancel it if queued (Tab to autocomplete)" -ForegroundColor Gray
    Write-Host "    /stop all         stop the running mirror and clear the queue" -ForegroundColor Gray
    Write-Host "    /help             show this list" -ForegroundColor Gray
    Write-Host "    /exit             quit (or just press Enter)" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-QuestMirror {
    param([string]$RawName, [int]$PresetExeChoice = 0, [bool]$Interactive = $true)

    $forcePick = $false
    if ($RawName -match '^(.*?)\s+--?pick$') {
        $RawName = $Matches[1].Trim()
        $forcePick = $true
    }

    Write-Step "Resolving `"$RawName`""

    $apps = Get-DetectableApps

    $matches = Find-GameMatch -Apps $apps -Query $RawName
    if ($matches.Count -eq 0 -or $matches[0].Score -lt 75) {
        $canonical = Resolve-SteamCanonicalName -RawName $RawName
        if ($canonical -and $canonical -ne $RawName) {
            Write-Meta "Steam suggests `"$canonical`" - retrying..."
            $retry = Find-GameMatch -Apps $apps -Query $canonical
            if ($retry.Count -gt 0 -and $retry[0].Score -gt $matches[0].Score) {
                $matches = $retry
            }
        }
    }

    if ($matches.Count -eq 0) {
        Write-Err2 "No matching game found for `"$RawName`""
        return
    }

    $chosen = $matches[0].App
    if ($matches.Count -gt 1 -and $matches[0].Score -lt 90) {
        Write-Warn2 "Multiple possible matches:"
        for ($i = 0; $i -lt $matches.Count; $i++) {
            Write-Host ("      [{0}] {1}" -f ($i + 1), $matches[$i].App.name) -ForegroundColor Gray
        }
        if ($Interactive) {
            Write-Host -NoNewline "    Pick one (Enter for [1]): " -ForegroundColor DarkGray
            $pick = Read-Host
            $index = 0
            $valid = $pick -and [int]::TryParse($pick, [ref]$index) -and $index -ge 1 -and $index -le $matches.Count
            if ($valid) {
                $chosen = $matches[$index - 1].App
                Write-Ok "Using [$index] $($chosen.name)"
            } elseif ($pick) {
                Write-Meta "'$pick' isn't valid (1-$($matches.Count)), defaulting to [1]"
            }
        } else {
            Write-Meta "Non-interactive, defaulting to [1] $($chosen.name)"
        }
    } else {
        Write-Ok "Matched $($chosen.name)"
    }

    $exe = Select-BestExecutable -Executables $chosen.executables -PresetChoice $PresetExeChoice -ForcePrompt $forcePick
    if (-not $exe) {
        $platformLabel = if ($script:PlatformOS -eq 'darwin') { 'macOS' } else { 'Windows' }
        Write-Err2 "`"$($chosen.name)`" has no known $platformLabel executable in Discord's list"
        return
    }

    $exeName = Split-Path $exe.name -Leaf
    Write-Ok "Target exe: $exeName"

    if ($Interactive -and (Test-MirrorActive)) {
        $script:MirrorQueue.Enqueue([PSCustomObject]@{ ExeName = $exeName; DisplayName = $chosen.name })
        Write-Ok "Queued `"$($chosen.name)`" - starts automatically once the current mirror finishes (position $($script:MirrorQueue.Count))"
        return
    }

    Start-MirrorForGame -ExeName $exeName -DisplayName $chosen.name
}

Initialize-Platform

if ($GameName) {
    try {
        Invoke-QuestMirror -RawName $GameName -PresetExeChoice $ExeChoice -Interactive $false
    } catch {
        Write-Err2 "Unexpected error: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-BigBanner
    $platformLabel = if ($script:PlatformOS -eq 'darwin') { 'macOS' } else { 'Windows' }
    Write-Meta "Platform: $platformLabel"
    Write-Meta "Each mirror runs ~17.5 min. Type /help for commands."

    while ($true) {
        Write-Host ""
        $gameInput = Read-MirrorCommand

        if ([string]::IsNullOrWhiteSpace($gameInput) -or $gameInput.Trim() -eq '/exit') {
            break
        }

        switch -Regex ($gameInput.Trim()) {
            '^/help$' { Show-Help; continue }
            '^/status$' { Show-ActiveMirrors; continue }
            '^/stop\s+all$' { Stop-AllMirrors; continue }
            '^/stop\s+(.+)$' { Stop-Mirror -Query $Matches[1].Trim(); continue }
            default {
                Write-Divider
                try {
                    Invoke-QuestMirror -RawName $gameInput -Interactive $true
                } catch {
                    Write-Err2 "Unexpected error: $($_.Exception.Message)"
                }
                continue
            }
        }
    }

    Write-Host ""
    if ($script:MirrorQueue.Count -gt 0) {
        Write-Warn2 "$($script:MirrorQueue.Count) queued game(s) will NOT start - the queue only advances while this window is open"
    }
    Write-Meta "Bye - a running mirror keeps going until it expires or you /stop it."
}
