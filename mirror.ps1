# Discord Quest Game Mirror
# Interactive: irm https://raw.githubusercontent.com/KiarTV/Discord-Quest/master/mirror.ps1 | iex
# Non-interactive (scripting/testing): .\mirror.ps1 -GameName "Roblox" -ExeChoice 2
#
# Resolves a raw game name to the exact .exe filename Discord's Quest detection
# looks for, then launches a renamed copy of a harmless stub executable so a
# process with that image name is running. Only affects your own local
# Discord client's Quest progress detection - no network/account tampering.

param(
    [string]$GameName,
    [int]$ExeChoice = 0
)

$ErrorActionPreference = 'Stop'

$CacheDir = Join-Path $env:LOCALAPPDATA 'quest-mirror'
$CacheFile = Join-Path $CacheDir 'detectable_apps.json'
$MirrorsDir = Join-Path $CacheDir 'mirrors'
$CacheMaxAgeHours = 24
$StubSource = Join-Path $env:WINDIR 'System32\cmd.exe'
$MirrorDurationSeconds = [int](17.5 * 60)
$Version = '1.0.0'

# FIFO of games waiting for the currently running mirror to finish - only one
# mirror runs at a time, so anything requested while one is active gets
# queued here instead of launching immediately.
$script:MirrorQueue = New-Object System.Collections.Generic.Queue[object]

# ---------------------------------------------------------------------------
# UI kit
# ---------------------------------------------------------------------------

$script:Glyph = @{ Ok = [char]0x2713; Warn = [char]0x26A0; Err = [char]0x2717; Step = [char]0x25B8 }

$script:HRule = [char]0x2500

function Write-Divider { Write-Host (([string]$script:HRule) * 46) -ForegroundColor DarkGray }

# Block letters built from [char] codepoints (not literal Unicode text) so the
# art can't be corrupted by Windows PowerShell 5.1 misreading the file's
# encoding. Each letter is a 6-row array; widths verified to line up.
function J { param([int[]]$Codes) -join ($Codes | ForEach-Object { [char]$_ }) }

$FBc = 0x2588  # █
$V   = 0x2551  # ║
$UR  = 0x2557  # ╗  (down+left)
$UL  = 0x2554  # ╔  (down+right)
$LR  = 0x255D  # ╝  (up+left)
$LL  = 0x255A  # ╚  (up+right)
$H   = 0x2550  # ═
$SP  = 0x0020

$script:BigLetters = @{
    M = @(
        (J @($FBc,$FBc,$FBc,$UR,$SP,$SP,$SP,$FBc,$FBc,$FBc,$UR)),
        (J @($FBc,$FBc,$FBc,$FBc,$UR,$SP,$FBc,$FBc,$FBc,$FBc,$V)),
        (J @($FBc,$FBc,$UL,$FBc,$FBc,$FBc,$FBc,$UL,$FBc,$FBc,$V)),
        (J @($FBc,$FBc,$V,$LL,$FBc,$FBc,$UL,$LR,$FBc,$FBc,$V)),
        (J @($FBc,$FBc,$V,$SP,$LL,$H,$LR,$SP,$FBc,$FBc,$V)),
        (J @($LL,$H,$LR,$SP,$SP,$SP,$SP,$SP,$LL,$H,$LR))
    )
    I = @(
        (J @($FBc,$FBc,$UR)),
        (J @($FBc,$FBc,$V)),
        (J @($FBc,$FBc,$V)),
        (J @($FBc,$FBc,$V)),
        (J @($FBc,$FBc,$V)),
        (J @($LL,$H,$LR))
    )
    R = @(
        (J @($FBc,$FBc,$FBc,$FBc,$FBc,$FBc,$UR,$SP)),
        (J @($FBc,$FBc,$UL,$H,$H,$FBc,$FBc,$UR)),
        (J @($FBc,$FBc,$FBc,$FBc,$FBc,$FBc,$UL,$LR)),
        (J @($FBc,$FBc,$UL,$H,$H,$FBc,$FBc,$UR)),
        (J @($FBc,$FBc,$V,$SP,$SP,$FBc,$FBc,$V)),
        (J @($LL,$H,$LR,$SP,$SP,$LL,$H,$LR))
    )
    O = @(
        (J @($SP,$FBc,$FBc,$FBc,$FBc,$FBc,$FBc,$UR,$SP)),
        (J @($FBc,$FBc,$UL,$H,$H,$H,$FBc,$FBc,$UR)),
        (J @($FBc,$FBc,$V,$SP,$SP,$SP,$FBc,$FBc,$V)),
        (J @($FBc,$FBc,$V,$SP,$SP,$SP,$FBc,$FBc,$V)),
        (J @($LL,$FBc,$FBc,$FBc,$FBc,$FBc,$FBc,$UL,$LR)),
        (J @($SP,$LL,$H,$H,$H,$H,$H,$LR,$SP))
    )
}

function Write-BigBanner {
    $word = 'M', 'I', 'R', 'R', 'O', 'R'
    Write-Host ""
    for ($row = 0; $row -lt 6; $row++) {
        $line = '  ' + (($word | ForEach-Object { $script:BigLetters[$_][$row] }) -join '')
        Write-Host $line -ForegroundColor Cyan
    }
    Write-Host ""
    Write-Host '  Discord Quest Mirror ' -ForegroundColor White -NoNewline
    Write-Host "v$Version" -ForegroundColor DarkGray
    Write-Host '  Make Discord see a game that is not there' -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Step  { param([string]$Text) Write-Host "$($script:Glyph.Step) $Text" -ForegroundColor White }
function Write-Ok    { param([string]$Text) Write-Host "  $($script:Glyph.Ok) $Text" -ForegroundColor Green }
function Write-Warn2 { param([string]$Text) Write-Host "  $($script:Glyph.Warn) $Text" -ForegroundColor Yellow }
function Write-Err2  { param([string]$Text) Write-Host "  $($script:Glyph.Err) $Text" -ForegroundColor Red }
function Write-Meta  { param([string]$Text) Write-Host "  $Text" -ForegroundColor DarkGray }

function Format-TimeAgo {
    param([datetime]$Since)
    $span = (Get-Date) - $Since
    if ($span.TotalMinutes -lt 1) { return "just now" }
    if ($span.TotalHours -lt 1) { return "$([int]$span.TotalMinutes)m ago" }
    return "$([int]$span.TotalHours)h ago"
}

function Invoke-WithSpinner {
    param([scriptblock]$Action, [string]$Message)

    $frames = [char[]]@(0x280B, 0x2819, 0x2839, 0x2838, 0x283C, 0x2834, 0x2826, 0x2827, 0x2807, 0x280F)
    $job = Start-Job -ScriptBlock $Action
    $i = 0
    try {
        while ($job.State -eq 'Running') {
            Write-Host -NoNewline ("`r{0} {1}" -f $frames[$i % $frames.Count], $Message) -ForegroundColor Cyan
            Start-Sleep -Milliseconds 80
            $i++
        }
        $result = Receive-Job -Job $job -ErrorAction Stop
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        Write-Host ("`r" + (' ' * ($Message.Length + 4)) + "`r") -NoNewline
    }
    return $result
}

# ---------------------------------------------------------------------------
# Core logic
# ---------------------------------------------------------------------------

function Get-DetectableApps {
    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    if ((Test-Path $CacheFile) -and
        ((Get-Item $CacheFile).LastWriteTime -gt (Get-Date).AddHours(-$CacheMaxAgeHours))) {
        $age = Format-TimeAgo (Get-Item $CacheFile).LastWriteTime
        Write-Meta "Using cached game list (refreshed $age)"
        return Get-Content $CacheFile -Raw | ConvertFrom-Json
    }

    $apps = Invoke-WithSpinner -Message "Fetching Discord's detectable game list..." -Action {
        Invoke-RestMethod "https://discord.com/api/v10/applications/detectable"
    }
    $apps | ConvertTo-Json -Depth 10 | Set-Content $CacheFile
    Write-Meta "Cached $($apps.Count) known games"
    return $apps
}

function Resolve-SteamCanonicalName {
    param([string]$RawName)

    try {
        $encoded = [uri]::EscapeDataString($RawName)
        $url = "https://store.steampowered.com/api/storesearch/?term=$encoded&cc=us&l=en"
        $result = Invoke-WithSpinner -Message "Checking Steam for a closer match..." -Action {
            Invoke-RestMethod $using:url -TimeoutSec 5
        }
        if ($result.items -and $result.items.Count -gt 0) {
            return $result.items[0].name
        }
    } catch {
        Write-Meta "Steam lookup skipped ($($_.Exception.Message))"
    }
    return $null
}

function Get-MatchScore {
    param([string]$Query, [string]$Candidate)

    $q = $Query.ToLowerInvariant().Trim()
    $c = $Candidate.ToLowerInvariant().Trim()

    if ($c -eq $q) { return 100 }
    if ($c.StartsWith($q)) { return 90 }
    if ($c.Contains($q)) { return 75 }

    $qWords = $q -split '\s+'
    $matched = ($qWords | Where-Object { $c.Contains($_) }).Count
    if ($qWords.Count -eq 0) { return 0 }
    return [math]::Round(60 * $matched / $qWords.Count)
}

function Find-GameMatch {
    param($Apps, [string]$Query)

    $scored = foreach ($app in $Apps) {
        $names = @($app.name) + @($app.aliases)
        $best = ($names | ForEach-Object { Get-MatchScore -Query $Query -Candidate $_ } | Measure-Object -Maximum).Maximum
        if ($best -gt 0) {
            [PSCustomObject]@{ App = $app; Score = $best }
        }
    }

    return $scored | Sort-Object -Property Score -Descending | Select-Object -First 8
}

function Select-BestExecutable {
    param($Executables, [int]$PresetChoice = 0)

    $win = @($Executables | Where-Object { $_.os -eq 'win32' -and -not $_.is_launcher })
    if ($win.Count -eq 0) {
        $win = @($Executables | Where-Object { $_.os -eq 'win32' })
    }
    if ($win.Count -eq 0) { return $null }
    if ($win.Count -eq 1) { return $win[0] }

    # Prefer a top-level exe (no subfolder) as the most likely main game binary.
    $topLevel = @($win | Where-Object { $_.name -notmatch '/' })
    $ordered = if ($topLevel.Count -gt 0) { $topLevel + ($win | Where-Object { $_.name -match '/' }) } else { $win }

    # Discord's detection just checks the process name against its list, so
    # any of these is equally "correct" - no need to ask, always take the
    # first (unless a specific one was requested via -ExeChoice).
    if ($PresetChoice -ge 1 -and $PresetChoice -le $ordered.Count) {
        Write-Meta "Multiple executables found - using [$PresetChoice] $($ordered[$PresetChoice - 1].name) (preset)"
        return $ordered[$PresetChoice - 1]
    }
    Write-Meta "Multiple executables found - using $($ordered[0].name)"
    return $ordered[0]
}

function Deploy-Stub {
    param([string]$ExeName)

    if (-not (Test-Path $MirrorsDir)) {
        New-Item -ItemType Directory -Path $MirrorsDir -Force | Out-Null
    }
    if (-not (Test-Path $StubSource)) {
        throw "Stub source not found: $StubSource"
    }

    $target = Join-Path $MirrorsDir $ExeName
    Copy-Item -Path $StubSource -Destination $target -Force
    return $target
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-DeElevated {
    param([string]$FilePath, [string]$Arguments)

    # A standard-integrity Discord process can't properly see into a
    # higher-integrity (elevated) one - UIPI blocks it. If this script is
    # running elevated, the stub must still launch at standard integrity, so
    # hand the launch to a Limited-rights scheduled task instead of spawning
    # it directly (which would inherit our elevated token).
    $escapedPath = $FilePath.Replace("'", "''")
    $escapedArgs = $Arguments.Replace("'", "''")
    $inner = "Start-Process -FilePath '$escapedPath' -ArgumentList '$escapedArgs' -WindowStyle Normal"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($inner))

    $taskName = "QuestMirror_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -EncodedCommand $encoded"
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Limited
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $taskName
        $deadline = (Get-Date).AddSeconds(5)
        $proc = $null
        while ((Get-Date) -lt $deadline -and -not $proc) {
            Start-Sleep -Milliseconds 300
            $proc = Get-Process | Where-Object { $_.Path -eq $FilePath } | Select-Object -First 1
        }
        return $proc
    } finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class QuestMirrorNative {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@

function Find-MirrorWindowHandle {
    param([int]$ProcessId, [string]$ExeName)

    # The renamed process itself, a classic conhost.exe child, or - on
    # machines where Windows Terminal is the default terminal app - a
    # WindowsTerminal.exe window can each end up owning the actual HWND,
    # so all three have to be checked (confirmed via live testing).
    $deadline = (Get-Date).AddSeconds(6)
    while ((Get-Date) -lt $deadline) {
        $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowHandle -ne [IntPtr]::Zero) { return $proc.MainWindowHandle }

        $conhosts = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId AND Name='conhost.exe'" -ErrorAction SilentlyContinue
        foreach ($c in $conhosts) {
            $chProc = Get-Process -Id $c.ProcessId -ErrorAction SilentlyContinue
            if ($chProc -and $chProc.MainWindowHandle -ne [IntPtr]::Zero) { return $chProc.MainWindowHandle }
        }

        $wt = Get-Process WindowsTerminal -ErrorAction SilentlyContinue |
            Where-Object { $_.MainWindowTitle -like "*$ExeName*" -and $_.MainWindowHandle -ne [IntPtr]::Zero } |
            Select-Object -First 1
        if ($wt) { return $wt.MainWindowHandle }

        Start-Sleep -Milliseconds 300
    }
    return [IntPtr]::Zero
}

function Hide-MirrorWindow {
    param([int]$ProcessId, [string]$ExeName)

    $hwnd = Find-MirrorWindowHandle -ProcessId $ProcessId -ExeName $ExeName
    if ($hwnd -eq [IntPtr]::Zero) {
        Write-Warn2 "Couldn't locate the mirror's window to hide it - it may briefly flash on screen"
        return
    }
    # SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE. The window stays in its
    # normal (restored) state - Discord only counts the mirror as running
    # while it's not minimized - just relocated off every monitor.
    [QuestMirrorNative]::SetWindowPos($hwnd, [IntPtr]::Zero, -32000, -32000, 0, 0, 0x15) | Out-Null
}

function Start-Mirror {
    param([string]$ExePath)

    # Discord only counts the mirror as running while its window is in a
    # normal (restored) state - Minimized reads as not-running (confirmed
    # via live testing). So launch visibly, then move the window off every
    # monitor instead of minimizing it.
    $seconds = [int]$MirrorDurationSeconds
    $mirrorArgs = "/c timeout /t $seconds /nobreak >nul"
    $exeName = Split-Path $ExePath -Leaf

    if (Test-IsElevated) {
        Write-Meta "Running elevated - launching mirror at standard integrity so Discord can see it"
        $proc = Start-DeElevated -FilePath $ExePath -Arguments $mirrorArgs
        if (-not $proc) {
            Write-Err2 "De-elevated launch didn't produce a matching process in time"
            return [PSCustomObject]@{ Id = $null; Alive = $false }
        }
    } else {
        $proc = Start-Process -FilePath $ExePath -ArgumentList $mirrorArgs -WindowStyle Normal -PassThru
    }

    Hide-MirrorWindow -ProcessId $proc.Id -ExeName $exeName

    Start-Sleep -Milliseconds 1200
    $alive = $false
    try { $alive = -not (Get-Process -Id $proc.Id -ErrorAction Stop).HasExited } catch { $alive = $false }

    if (-not $alive) {
        Write-Err2 "Process exited immediately after launch (PID $($proc.Id) is gone)"
        Write-Meta "Likely cause: antivirus killing a renamed system exe on sight"
        Write-Meta "Check Windows Security -> Protection history, then exclude: $MirrorsDir"
    }

    return [PSCustomObject]@{ Id = $proc.Id; Alive = $alive }
}

function Get-ActiveMirrorProcesses {
    return Get-Process | Where-Object { $_.Path -and $_.Path.StartsWith($MirrorsDir, [StringComparison]::OrdinalIgnoreCase) }
}

function Test-MirrorActive {
    return [bool](Get-ActiveMirrorProcesses)
}

function Stop-Mirror {
    param([string]$ExeName)

    $procs = Get-Process | Where-Object { $_.Path -and (Split-Path $_.Path -Leaf) -eq $ExeName }
    if (-not $procs) {
        Write-Warn2 "No running mirror named '$ExeName' found"
        return
    }
    foreach ($p in $procs) {
        Stop-Process -Id $p.Id -Force
        Write-Ok "Stopped $ExeName (PID $($p.Id))"
    }
}

function Stop-AllMirrors {
    $procs = Get-ActiveMirrorProcesses
    if (-not $procs) {
        Write-Warn2 "No active mirrors to stop"
        return
    }
    foreach ($p in $procs) {
        $name = Split-Path $p.Path -Leaf
        Stop-Process -Id $p.Id -Force
        Write-Ok "Stopped $name (PID $($p.Id))"
    }
}

function Show-ActiveMirrors {
    $procs = Get-ActiveMirrorProcesses
    if (-not $procs) {
        Write-Meta "No active mirrors."
    } else {
        Write-Host ""
        Write-Host ("  {0,-28} {1,-8} {2}" -f 'EXE', 'PID', 'EXPIRES') -ForegroundColor DarkGray
        foreach ($p in $procs) {
            $name = Split-Path $p.Path -Leaf
            $expires = $p.StartTime.AddSeconds($MirrorDurationSeconds).ToString('HH:mm:ss')
            Write-Host ("  {0,-28} {1,-8} {2}" -f $name, $p.Id, $expires) -ForegroundColor White
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

function Show-Help {
    Write-Host ""
    Write-Host "  Commands" -ForegroundColor DarkCyan
    Write-Host "    <game name>       start a mirror, or queue it if one's already running" -ForegroundColor Gray
    Write-Host "    /status           list active mirrors and the queue" -ForegroundColor Gray
    Write-Host "    /stop <exe.exe>   stop one mirror" -ForegroundColor Gray
    Write-Host "    /stop all         stop every active mirror" -ForegroundColor Gray
    Write-Host "    /help             show this list" -ForegroundColor Gray
    Write-Host "    /exit             quit (or just press Enter)" -ForegroundColor Gray
    Write-Host ""
}

function Invoke-QueuePump {
    if ($script:MirrorQueue.Count -eq 0 -or (Test-MirrorActive)) { return }

    $next = $script:MirrorQueue.Dequeue()
    Write-Host ""
    Write-Step "Starting queued mirror: $($next.DisplayName)"
    Start-MirrorForGame -ExeName $next.ExeName -DisplayName $next.DisplayName
}

function Read-MirrorCommand {
    # A plain Read-Host blocks the thread, and .NET timer/event callbacks
    # don't get pumped reliably while it's blocked (confirmed via live
    # testing - a queued mirror never auto-started while sitting idle at a
    # Read-Host prompt). Polling for keystrokes here instead lets the queue
    # advance itself while the prompt sits idle with nothing typed.
    $prompt = { Write-Host -NoNewline "quest-mirror " -ForegroundColor DarkCyan; Write-Host -NoNewline "> " -ForegroundColor DarkGray }
    & $prompt
    $buffer = New-Object System.Text.StringBuilder

    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Enter') {
                Write-Host ""
                return $buffer.ToString()
            } elseif ($key.Key -eq 'Backspace') {
                if ($buffer.Length -gt 0) {
                    $buffer.Length -= 1
                    Write-Host -NoNewline "`b `b"
                }
            } elseif (-not [char]::IsControl($key.KeyChar)) {
                [void]$buffer.Append($key.KeyChar)
                Write-Host -NoNewline $key.KeyChar
            }
            continue
        }

        Start-Sleep -Milliseconds 150
        $before = $script:MirrorQueue.Count
        Invoke-QueuePump
        if ($script:MirrorQueue.Count -lt $before) {
            # A queued mirror just started - redraw the prompt line so the
            # user's partially-typed input isn't lost underneath the output.
            Write-Host ""
            & $prompt
            Write-Host -NoNewline $buffer.ToString()
        }
    }
}

function Start-MirrorForGame {
    param([string]$ExeName, [string]$DisplayName)

    $target = Deploy-Stub -ExeName $ExeName
    $proc = Start-Mirror -ExePath $target

    if ($proc.Alive) {
        $expires = (Get-Date).AddSeconds($MirrorDurationSeconds).ToString('HH:mm:ss')
        Write-Ok "Mirror running - PID $($proc.Id), expires ~$expires"
        Write-Meta "Stop early with: /stop $ExeName"
    }
}

function Invoke-QuestMirror {
    param([string]$RawName, [int]$PresetExeChoice = 0, [bool]$Interactive = $true)

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

    $exe = Select-BestExecutable -Executables $chosen.executables -PresetChoice $PresetExeChoice
    if (-not $exe) {
        Write-Err2 "`"$($chosen.name)`" has no known Windows executable in Discord's list"
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

# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

if ($GameName) {
    try {
        Invoke-QuestMirror -RawName $GameName -PresetExeChoice $ExeChoice -Interactive $false
    } catch {
        Write-Err2 "Unexpected error: $($_.Exception.Message)"
        exit 1
    }
} else {
    Write-BigBanner
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
            '^/stop\s+(.+)$' { Stop-Mirror -ExeName $Matches[1].Trim(); continue }
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
    Write-Meta "Bye - active mirrors keep running until they expire or you /stop them."
}
