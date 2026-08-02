# ---------------------------------------------------------------------------
# macOS implementation - UNVERIFIED against Discord's real Quest detection.
#
# The Windows half of this script works because Discord's Windows detector
# enumerates top-level windows and matches the owning process' image name -
# confirmed by live testing against real Quests. Discord's macOS detector is
# a different, closed-source code path, and nobody involved in this repo has
# confirmed exactly what it keys on (running process name via ps/libproc?
# the app bundle's CFBundleIdentifier from Info.plist? something else?).
#
# This implementation takes the most likely guess given how the Windows side
# behaves: a running process whose name matches the executable name from
# Discord's detectable-apps list. It deliberately does NOT try to fake a
# window - a bare CLI process has no window at all, and unlike Windows,
# nothing suggests Discord's Mac client requires one.
#
# If a mirror doesn't get picked up as a running game on your machine,
# that's useful signal either way - please open an issue with what you
# tried and whether Quest progress moved.
# ---------------------------------------------------------------------------

function Initialize-Platform-MacOS {
    $script:CacheDir = Join-Path $HOME 'Library/Caches/quest-mirror'
    $script:CacheFile = Join-Path $script:CacheDir 'detectable_apps.json'
    $script:MirrorsDir = Join-Path $script:CacheDir 'mirrors'
    # /bin/sleep IS the mirror - it already accepts a duration and exits on
    # its own, so (unlike Windows' cmd.exe) no wrapper arguments are needed.
    $script:StubSource = '/bin/sleep'
    $script:AppOsKey = 'darwin'
}

function Deploy-Stub-MacOS {
    param([string]$ExeName)

    if (-not (Test-Path $script:MirrorsDir)) {
        New-Item -ItemType Directory -Path $script:MirrorsDir -Force | Out-Null
    }
    if (-not (Test-Path $script:StubSource)) {
        throw "Stub source not found: $script:StubSource"
    }

    $target = Join-Path $script:MirrorsDir $ExeName
    Copy-Item -Path $script:StubSource -Destination $target -Force
    # Copy-Item doesn't reliably preserve the executable bit across
    # filesystems/pwsh versions - set it explicitly rather than assume.
    & chmod 755 $target
    return $target
}

function Start-Mirror-MacOS {
    param([string]$ExePath)

    $seconds = [int]$MirrorDurationSeconds
    $proc = Start-Process -FilePath $ExePath -ArgumentList "$seconds" -PassThru

    Start-Sleep -Milliseconds 1200
    $alive = $false
    try { $alive = -not (Get-Process -Id $proc.Id -ErrorAction Stop).HasExited } catch { $alive = $false }

    if (-not $alive) {
        Write-Err2 "Process exited immediately after launch (PID $($proc.Id) is gone)"
        Write-Meta "Check Gatekeeper isn't blocking the renamed binary in: $script:MirrorsDir"
    }

    return [PSCustomObject]@{ Id = $proc.Id; Alive = $alive }
}
