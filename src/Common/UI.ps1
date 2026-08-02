# ---------------------------------------------------------------------------
# UI kit - console output helpers, banner, spinner, and the cross-platform
# VT/ANSI enable step everything below (InputLoop.ps1's completion menu)
# depends on.
# ---------------------------------------------------------------------------

$script:Glyph = @{ Ok = [char]0x2713; Warn = [char]0x26A0; Err = [char]0x2717; Step = [char]0x25B8 }

$script:HRule = [char]0x2500
$script:Esc = [char]27

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

# Cached tri-state ($null = not probed yet). Enabling VT lets the /stop
# completion menu draw real rows below the prompt using only *relative*
# ANSI cursor moves (save/restore, next-line, line-clear) - unlike
# [Console]::CursorTop/SetCursorPosition, those aren't the ones that desync
# from the real cursor under Windows Terminal's ConPTY translation layer
# (see the comment on Read-MirrorCommand in InputLoop.ps1 for why that
# matters here). Any failure leaves $script:UseMenu false for the whole
# session and the original single-line ghost-text path runs unchanged.
$script:VtEnabled = $null

function Enable-VirtualTerminal {
    if ($null -ne $script:VtEnabled) { return $script:VtEnabled }
    if ([Console]::IsOutputRedirected) { $script:VtEnabled = $false; return $false }

    if ($script:PlatformOS -eq 'win32') {
        # Windows consoles need ENABLE_VIRTUAL_TERMINAL_PROCESSING flipped on
        # explicitly - see Platform/Windows.ps1.
        $script:VtEnabled = Enable-VirtualTerminal-Windows
    } else {
        # Unix terminals (Terminal.app, iTerm2, and effectively everything
        # else macOS/Linux users run) interpret ANSI/VT sequences natively -
        # there's no console-mode flag to flip the way Windows needs one.
        $script:VtEnabled = $true
    }
    return $script:VtEnabled
}
