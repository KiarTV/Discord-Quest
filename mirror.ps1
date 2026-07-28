# Discord Quest Game Mirror
# Run with: irm https://raw.githubusercontent.com/<you>/<repo>/main/mirror.ps1 | iex
#
# Resolves a raw game name to the exact .exe filename Discord's Quest detection
# looks for, then launches a renamed copy of a harmless stub executable so a
# process with that image name is running. Only affects your own local
# Discord client's Quest progress detection - no network/account tampering.

$ErrorActionPreference = 'Stop'

$CacheDir = Join-Path $env:LOCALAPPDATA 'quest-mirror'
$CacheFile = Join-Path $CacheDir 'detectable_apps.json'
$MirrorsDir = Join-Path $CacheDir 'mirrors'
$CacheMaxAgeHours = 24
$StubSource = Join-Path $env:WINDIR 'System32\timeout.exe'
# Quests need ~15 min of detection; timeout.exe is a console app (no desktop
# session required) so several can run in parallel, one per queued game.
$MirrorDurationSeconds = 17.5 * 60

function Get-DetectableApps {
    if (-not (Test-Path $CacheDir)) {
        New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
    }

    if ((Test-Path $CacheFile) -and
        ((Get-Item $CacheFile).LastWriteTime -gt (Get-Date).AddHours(-$CacheMaxAgeHours))) {
        Write-Host "Using cached game list..." -ForegroundColor DarkGray
        return Get-Content $CacheFile -Raw | ConvertFrom-Json
    }

    Write-Host "Fetching Discord's detectable game list..." -ForegroundColor DarkGray
    $apps = Invoke-RestMethod "https://discord.com/api/v10/applications/detectable"
    $apps | ConvertTo-Json -Depth 10 | Set-Content $CacheFile
    return $apps
}

function Resolve-SteamCanonicalName {
    param([string]$RawName)

    try {
        $encoded = [uri]::EscapeDataString($RawName)
        $result = Invoke-RestMethod "https://store.steampowered.com/api/storesearch/?term=$encoded&cc=us&l=en" -TimeoutSec 5
        if ($result.items -and $result.items.Count -gt 0) {
            return $result.items[0].name
        }
    } catch {
        Write-Host "Steam lookup skipped ($($_.Exception.Message))" -ForegroundColor DarkGray
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
    param($Executables)

    $win = @($Executables | Where-Object { $_.os -eq 'win32' -and -not $_.is_launcher })
    if ($win.Count -eq 0) {
        $win = @($Executables | Where-Object { $_.os -eq 'win32' })
    }
    if ($win.Count -eq 0) { return $null }
    if ($win.Count -eq 1) { return $win[0] }

    # Prefer a top-level exe (no subfolder) as the most likely main game binary.
    $topLevel = @($win | Where-Object { $_.name -notmatch '/' })
    $ordered = if ($topLevel.Count -gt 0) { $topLevel + ($win | Where-Object { $_.name -match '/' }) } else { $win }

    Write-Host ""
    Write-Host "Multiple Windows executables found for this game:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        Write-Host "  [$($i + 1)] $($ordered[$i].name)"
    }
    $pick = Read-Host "Pick one (Enter for [1])"
    $index = 0
    if ($pick -and [int]::TryParse($pick, [ref]$index) -and $index -ge 1 -and $index -le $ordered.Count) {
        return $ordered[$index - 1]
    }
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

function Start-Mirror {
    param([string]$ExePath)

    $seconds = [int]$MirrorDurationSeconds
    $proc = Start-Process -FilePath $ExePath -ArgumentList "/T $seconds /NOBREAK" -WindowStyle Hidden -PassThru
    return $proc
}

function Stop-Mirror {
    param([string]$ExeName)

    $procs = Get-Process | Where-Object {
        $_.Path -and (Split-Path $_.Path -Leaf) -eq $ExeName
    }
    if (-not $procs) {
        Write-Host "No running process named '$ExeName' found." -ForegroundColor Yellow
        return
    }
    foreach ($p in $procs) {
        Stop-Process -Id $p.Id -Force
        Write-Host "Stopped $ExeName (PID $($p.Id))" -ForegroundColor Green
    }
}

function Invoke-QuestMirror {
    param([string]$RawName)

    if ($RawName.ToLowerInvariant().StartsWith('stop ')) {
        $exeName = $RawName.Substring(5).Trim()
        Stop-Mirror -ExeName $exeName
        return
    }

    $apps = Get-DetectableApps

    $matches = Find-GameMatch -Apps $apps -Query $RawName
    if ($matches.Count -eq 0 -or $matches[0].Score -lt 75) {
        $canonical = Resolve-SteamCanonicalName -RawName $RawName
        if ($canonical -and $canonical -ne $RawName) {
            Write-Host "Steam suggests: '$canonical' - retrying match..." -ForegroundColor DarkGray
            $retry = Find-GameMatch -Apps $apps -Query $canonical
            if ($retry.Count -gt 0 -and $retry[0].Score -gt $matches[0].Score) {
                $matches = $retry
            }
        }
    }

    if ($matches.Count -eq 0) {
        Write-Host "No matching game found for '$RawName'." -ForegroundColor Red
        return
    }

    $chosen = $matches[0].App
    if ($matches.Count -gt 1 -and $matches[0].Score -lt 90) {
        Write-Host ""
        Write-Host "Multiple possible matches:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $matches.Count; $i++) {
            Write-Host "  [$($i + 1)] $($matches[$i].App.name)"
        }
        $pick = Read-Host "Pick one (Enter for [1])"
        $index = 0
        if ($pick -and [int]::TryParse($pick, [ref]$index) -and $index -ge 1 -and $index -le $matches.Count) {
            $chosen = $matches[$index - 1].App
        }
    }

    $exe = Select-BestExecutable -Executables $chosen.executables
    if (-not $exe) {
        Write-Host "'$($chosen.name)' has no known Windows executable in Discord's list." -ForegroundColor Red
        return
    }

    $exeName = Split-Path $exe.name -Leaf
    Write-Host ""
    Write-Host "Matched: $($chosen.name)" -ForegroundColor Cyan
    Write-Host "Target exe: $exeName" -ForegroundColor Cyan

    $target = Deploy-Stub -ExeName $exeName
    $proc = Start-Mirror -ExePath $target
    $expires = (Get-Date).AddSeconds($MirrorDurationSeconds).ToString('HH:mm:ss')

    Write-Host ""
    Write-Host "Mirror running: $exeName (PID $($proc.Id), expires ~$expires)" -ForegroundColor Green
    Write-Host "To stop it early, run this script again and enter: stop $exeName" -ForegroundColor DarkGray
}

# --- Driver ---
Write-Host "=== Discord Quest Game Mirror ===" -ForegroundColor Magenta
Write-Host "Each mirror runs for ~17.5 min - queue as many games as you want, one per line." -ForegroundColor DarkGray
while ($true) {
    $gameInput = Read-Host "`nEnter game name (blank to finish, or 'stop <exe.exe>' to kill a running mirror)"
    if ([string]::IsNullOrWhiteSpace($gameInput)) {
        break
    }
    Invoke-QuestMirror -RawName $gameInput
}
