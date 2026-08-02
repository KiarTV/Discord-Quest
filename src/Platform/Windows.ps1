# ---------------------------------------------------------------------------
# Windows implementation - stub is a renamed copy of cmd.exe, kept alive via
# `timeout`, moved off-screen (not minimized) so Discord's window-owning
# process scan still counts it as running.
# ---------------------------------------------------------------------------

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class QuestMirrorNative {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class QuestMirrorConsole {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
}
"@

function Enable-VirtualTerminal-Windows {
    try {
        $STD_OUTPUT_HANDLE = -11
        $ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004
        $h = [QuestMirrorConsole]::GetStdHandle($STD_OUTPUT_HANDLE)
        if ($h -eq [IntPtr]::Zero) { return $false }
        $mode = 0
        if (-not [QuestMirrorConsole]::GetConsoleMode($h, [ref]$mode)) { return $false }
        if (($mode -band $ENABLE_VIRTUAL_TERMINAL_PROCESSING) -eq 0) {
            if (-not [QuestMirrorConsole]::SetConsoleMode($h, ($mode -bor $ENABLE_VIRTUAL_TERMINAL_PROCESSING))) { return $false }
        }
        return $true
    } catch {
        return $false
    }
}

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

function Initialize-Platform-Windows {
    $script:CacheDir = Join-Path $env:LOCALAPPDATA 'quest-mirror'
    $script:CacheFile = Join-Path $script:CacheDir 'detectable_apps.json'
    $script:MirrorsDir = Join-Path $script:CacheDir 'mirrors'
    $script:StubSource = Join-Path $env:WINDIR 'System32\cmd.exe'
    $script:AppOsKey = 'win32'
}

function Deploy-Stub-Windows {
    param([string]$ExeName)

    if (-not (Test-Path $script:MirrorsDir)) {
        New-Item -ItemType Directory -Path $script:MirrorsDir -Force | Out-Null
    }
    if (-not (Test-Path $script:StubSource)) {
        throw "Stub source not found: $script:StubSource"
    }

    $target = Join-Path $script:MirrorsDir $ExeName
    Copy-Item -Path $script:StubSource -Destination $target -Force
    return $target
}

function Start-Mirror-Windows {
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
        Write-Meta "Check Windows Security -> Protection history, then exclude: $script:MirrorsDir"
    }

    return [PSCustomObject]@{ Id = $proc.Id; Alive = $alive }
}

function Stop-MirrorProcess-Windows {
    param([int]$ProcessId)

    # The mirror stub is a renamed cmd.exe running `/c timeout ...` -
    # timeout.exe runs as a CHILD of that process, sharing its console.
    # Stop-Process on just the tracked PID doesn't cascade to children, so
    # timeout.exe (and the console/window it's still attached to) keeps
    # running for whatever's left of its ~17.5 minutes - and it's invisible
    # to /status the whole time, since its own Path is
    # System32\timeout.exe, not under $script:MirrorsDir. Confirmed via a
    # live report of exactly this: /stop reported success, but the process
    # was still running afterward.
    $children = Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    foreach ($child in $children) {
        Stop-Process -Id $child.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}
