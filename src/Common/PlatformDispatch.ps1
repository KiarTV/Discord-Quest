# ---------------------------------------------------------------------------
# Platform detection & dispatch - the only place that decides whether
# Platform/Windows.ps1 or Platform/MacOS.ps1 handles a given call. Both
# platform files are always loaded (this ships as one bundled script), so
# every platform-specific function is suffixed -Windows / -MacOS and is
# never called directly outside this dispatch layer.
# ---------------------------------------------------------------------------

function Get-PlatformOS {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        if ($IsMacOS) { return 'darwin' }
        if ($IsWindows) { return 'win32' }
        return 'linux'
    }
    # Windows PowerShell 5.1 (no $IsWindows/$IsMacOS) only ever runs on Windows.
    return 'win32'
}

# Sets $script:CacheDir, $script:CacheFile, $script:MirrorsDir,
# $script:StubSource and $script:AppOsKey (the "os" value Discord's
# detectable-apps executables list uses for this platform - 'win32' or
# 'darwin') by delegating to the matching Initialize-Platform-* function.
function Initialize-Platform {
    $script:PlatformOS = Get-PlatformOS

    switch ($script:PlatformOS) {
        'win32'  { Initialize-Platform-Windows }
        'darwin' { Initialize-Platform-MacOS }
        default {
            Write-Host "quest-mirror only supports Windows and macOS right now (detected: $script:PlatformOS)." -ForegroundColor Red
            exit 1
        }
    }

    if (-not (Test-Path $script:CacheDir)) {
        New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
    }
}

function Deploy-Stub {
    param([string]$ExeName)
    if ($script:PlatformOS -eq 'win32') { return Deploy-Stub-Windows -ExeName $ExeName }
    return Deploy-Stub-MacOS -ExeName $ExeName
}

function Start-Mirror {
    param([string]$ExePath)
    if ($script:PlatformOS -eq 'win32') { return Start-Mirror-Windows -ExePath $ExePath }
    return Start-Mirror-MacOS -ExePath $ExePath
}

function Stop-MirrorProcess {
    param([int]$ProcessId)
    if ($script:PlatformOS -eq 'win32') { Stop-MirrorProcess-Windows -ProcessId $ProcessId; return }
    Stop-MirrorProcess-MacOS -ProcessId $ProcessId
}
