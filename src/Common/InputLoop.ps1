# ---------------------------------------------------------------------------
# Dropdown completion menu - draws below the current input line using only
# relative ANSI/VT moves (save/restore cursor, cursor-next-line, line-clear),
# never [Console]::CursorTop/SetCursorPosition. Takes only plain strings and
# indices - no /stop-specific knowledge lives here - so it's general enough
# to reuse for other pickers (e.g. Select-BestExecutable's ambiguous-match
# prompt in Discovery.ps1) even though /stop is the primary user.
#
# Everything here is cross-platform: it only touches [Console] and the
# Enable-VirtualTerminal abstraction from UI.ps1, both of which work the
# same way (from this code's perspective) on Windows and macOS terminals.
# ---------------------------------------------------------------------------

function Clear-InlineOverlay {
    param([int]$Length)
    if ($Length -le 0) { return }
    Write-Host -NoNewline (' ' * $Length)
    [Console]::CursorLeft = [Console]::CursorLeft - $Length
}

function Write-InlineOverlay {
    param([string]$Text)
    if (-not $Text) { return 0 }
    Write-Host -NoNewline $Text -ForegroundColor DarkGray
    [Console]::CursorLeft = [Console]::CursorLeft - $Text.Length
    return $Text.Length
}

function Invoke-BelowCursor {
    param([int]$RowCount, [scriptblock]$RowRenderer)
    if ($RowCount -le 0) { return }
    Write-Host -NoNewline "$($script:Esc)[?25l$($script:Esc)[s"
    for ($i = 0; $i -lt $RowCount; $i++) {
        Write-Host -NoNewline "$($script:Esc)[1E$($script:Esc)[2K"
        & $RowRenderer $i
    }
    Write-Host -NoNewline "$($script:Esc)[u$($script:Esc)[?25h"
}

# Always emits exactly (MaxVisibleRows + 2) rows - a divider, the candidate
# rows, and a hint row - clearing every row on every call. That constant
# row-count is what guarantees a shorter/longer redraw never leaves stray
# characters behind, which is the failure mode this whole menu replaces.
function Show-CompletionMenu {
    param(
        [string[]]$Candidates,
        [string]$Filter,
        [int]$SelectedIndex,
        [int]$MaxVisibleRows = 5
    )
    $width = [Math]::Max(20, [Console]::WindowWidth - 1)
    Invoke-BelowCursor -RowCount ($MaxVisibleRows + 2) -RowRenderer {
        param($i)
        if ($i -eq 0) {
            Write-Host -NoNewline (([string]$script:HRule) * [Math]::Min(46, $width)) -ForegroundColor DarkGray
        } elseif ($i -le $MaxVisibleRows) {
            $idx = $i - 1
            if ($idx -lt $Candidates.Count) {
                $c = $Candidates[$idx]
                $maxLen = [Math]::Max(1, $width - 6)
                if ($c.Length -gt $maxLen) { $c = $c.Substring(0, [Math]::Max(1, $maxLen - 1)) + [char]0x2026 }
                $matchLen = [Math]::Min($Filter.Length, $c.Length)
                $matched = $c.Substring(0, $matchLen)
                $rest = $c.Substring($matchLen)
                if ($idx -eq $SelectedIndex) {
                    Write-Host -NoNewline "  $($script:Glyph.Step) " -ForegroundColor Cyan
                    Write-Host -NoNewline $matched -ForegroundColor Cyan
                    Write-Host -NoNewline $rest -ForegroundColor White
                } else {
                    Write-Host -NoNewline "    "
                    Write-Host -NoNewline $matched -ForegroundColor DarkCyan
                    Write-Host -NoNewline $rest -ForegroundColor DarkGray
                }
            }
        } else {
            $hint = "  Up/Dn move   Tab cycle   Enter select   Esc cancel"
            if ($Candidates.Count -gt $MaxVisibleRows) {
                $hint += "   (+$($Candidates.Count - $MaxVisibleRows) more)"
            }
            if ($hint.Length -gt $width) { $hint = $hint.Substring(0, $width) }
            Write-Host -NoNewline $hint -ForegroundColor DarkGray
        }
    }
}

function Hide-CompletionMenu {
    param([int]$TotalRows)
    Invoke-BelowCursor -RowCount $TotalRows -RowRenderer { param($i) }
}

# One-shot arrow-key list picker built on the same Show-CompletionMenu
# rendering as /stop - Up/Down (or Tab) move the highlight, Enter accepts,
# Escape accepts $DefaultIndex (same as pressing Enter with nothing typed in
# the old numbered prompts). Returns the chosen 0-based index, or $null if
# the menu can't be rendered here (no VT support, or the window's too short)
# - callers should fall back to their own plain prompt in that case, same as
# before this existed.
function Read-MenuSelection {
    param(
        [string[]]$Items,
        [int]$DefaultIndex = 0,
        [int]$MaxVisibleRows = 8
    )

    if ($Items.Count -eq 0) { return $null }
    $vtOk = Enable-VirtualTerminal
    $maxVisible = [Math]::Min($MaxVisibleRows, $Items.Count)
    $totalRows = $maxVisible + 2
    if (-not $vtOk -or (([Console]::WindowHeight - 3) -lt $totalRows)) { return $null }

    1..$totalRows | ForEach-Object { Write-Host "" }
    Write-Host -NoNewline ("$($script:Esc)[{0}A" -f $totalRows)

    $selected = $DefaultIndex
    Show-CompletionMenu -Candidates $Items -Filter '' -SelectedIndex $selected -MaxVisibleRows $maxVisible

    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { break }
        if ($key.Key -eq 'Escape') { $selected = $DefaultIndex; break }
        if ($key.Key -eq 'UpArrow') {
            $selected = ($selected - 1 + $Items.Count) % $Items.Count
        } elseif ($key.Key -eq 'DownArrow' -or $key.Key -eq 'Tab') {
            $selected = ($selected + 1) % $Items.Count
        } else {
            continue
        }
        Show-CompletionMenu -Candidates $Items -Filter '' -SelectedIndex $selected -MaxVisibleRows $maxVisible
    }

    Hide-CompletionMenu -TotalRows $totalRows
    return $selected
}

# Draws the "quest-mirror > " prompt (optionally re-echoing already-typed
# text, for the queue-pump mid-typing redraw). When a completion menu may be
# used this turn, it first prints $script:MenuTotalRows blank lines and
# moves back up over them with a *relative* cursor-up - this is what
# guarantees room exists below the prompt before anything ever tries to
# save/restore into that space, so the menu's own rendering never has to
# provoke a fresh scroll mid-render.
function Show-Prompt {
    param([string]$CurrentText = '')
    if ($script:UseMenu) {
        1..$script:MenuTotalRows | ForEach-Object { Write-Host "" }
        Write-Host -NoNewline ("$($script:Esc)[{0}A" -f $script:MenuTotalRows)
    }
    Write-Host -NoNewline "quest-mirror " -ForegroundColor DarkCyan
    Write-Host -NoNewline "> " -ForegroundColor DarkGray
    if ($CurrentText) { Write-Host -NoNewline $CurrentText }
}

function Read-MirrorCommand {
    # A plain Read-Host blocks the thread, and .NET timer/event callbacks
    # don't get pumped reliably while it's blocked (confirmed via live
    # testing - a queued mirror never auto-started while sitting idle at a
    # Read-Host prompt). Polling for keystrokes here instead lets the queue
    # advance itself while the prompt sits idle with nothing typed.
    #
    # /stop completion prefers a real dropdown menu (Show-CompletionMenu)
    # drawn below the prompt via Invoke-BelowCursor, which only ever uses
    # *relative* ANSI/VT cursor moves (save/restore, next-line). An earlier
    # version tried a second line using Console.CursorTop directly and hit
    # Windows Terminal's long-standing ConPTY bugs where CursorTop/
    # SetCursorPosition desyncs from the real cursor across rows - that's a
    # different, buggier code path than relative VT sequences, which the
    # terminal itself interprets natively. If VT mode can't be enabled (or
    # the window's too short to fit the menu), $script:UseMenu stays false
    # and this falls all the way back to the original single-row-only ghost
    # text + Tab-cycle counter, unchanged.
    $vtOk = Enable-VirtualTerminal
    $maxVisible = 5
    $script:MenuTotalRows = $maxVisible + 2
    $script:UseMenu = $false
    if ($vtOk) {
        $script:UseMenu = ([Console]::WindowHeight - 3) -ge $script:MenuTotalRows
        if (-not $script:UseMenu) {
            $maxVisible = [Console]::WindowHeight - 5
            $script:MenuTotalRows = $maxVisible + 2
            $script:UseMenu = $maxVisible -ge 1
        }
    }

    Show-Prompt
    $buffer = New-Object System.Text.StringBuilder
    $tabState = $null
    $overlayLen = 0
    $menuState = $null
    $menuSuppressed = $false
    $menuSuppressedFilter = ''
    $lastPump = Get-Date

    while ($true) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if (-not $script:UseMenu -and $key.Key -ne 'Tab') { $tabState = $null }

            Clear-InlineOverlay -Length $overlayLen
            $overlayLen = 0

            if ($key.Key -eq 'Enter') {
                if ($script:UseMenu -and $menuState -and $menuState.Candidates.Count -gt 0) {
                    $newText = "/stop " + $menuState.Candidates[$menuState.SelectedIndex]
                    if ($newText -ne $buffer.ToString()) {
                        $clear = ("`b" * $buffer.Length) + (' ' * $buffer.Length) + ("`b" * $buffer.Length)
                        Write-Host -NoNewline $clear
                        $buffer.Length = 0
                        [void]$buffer.Append($newText)
                        Write-Host -NoNewline $newText
                    }
                }
                if ($script:UseMenu) { Hide-CompletionMenu -TotalRows $script:MenuTotalRows }
                Write-Host ""
                return $buffer.ToString()
            } elseif ($key.Key -eq 'Backspace') {
                if ($buffer.Length -gt 0) {
                    $buffer.Length -= 1
                    Write-Host -NoNewline "`b `b"
                }
            } elseif ($key.Key -eq 'Tab') {
                if ($script:UseMenu) {
                    if ($buffer.ToString() -match '^/stop\s+(.*)$' -and $menuState -and $menuState.Candidates.Count -gt 0) {
                        $menuState.SelectedIndex = ($menuState.SelectedIndex + 1) % $menuState.Candidates.Count
                        $newText = "/stop " + $menuState.Candidates[$menuState.SelectedIndex]
                        $clear = ("`b" * $buffer.Length) + (' ' * $buffer.Length) + ("`b" * $buffer.Length)
                        Write-Host -NoNewline $clear
                        $buffer.Length = 0
                        [void]$buffer.Append($newText)
                        Write-Host -NoNewline $newText
                        Show-CompletionMenu -Candidates $menuState.Candidates -Filter $menuState.Filter -SelectedIndex $menuState.SelectedIndex -MaxVisibleRows $maxVisible
                    }
                } elseif ($buffer.ToString() -match '^/stop\s+(.*)$') {
                    if (-not $tabState) {
                        $candidates = Get-StopCandidates -Typed $Matches[1]
                        if ($candidates.Count -gt 0) {
                            $tabState = [PSCustomObject]@{ Candidates = $candidates; Index = 0 }
                        }
                    } else {
                        $tabState.Index = ($tabState.Index + 1) % $tabState.Candidates.Count
                    }
                    if ($tabState) {
                        $newText = "/stop " + $tabState.Candidates[$tabState.Index]
                        $clear = ("`b" * $buffer.Length) + (' ' * $buffer.Length) + ("`b" * $buffer.Length)
                        Write-Host -NoNewline $clear
                        $buffer.Length = 0
                        [void]$buffer.Append($newText)
                        Write-Host -NoNewline $newText
                    }
                }
            } elseif ($key.Key -eq 'UpArrow') {
                if ($script:UseMenu -and $menuState -and $menuState.Candidates.Count -gt 0) {
                    $menuState.SelectedIndex = ($menuState.SelectedIndex - 1 + $menuState.Candidates.Count) % $menuState.Candidates.Count
                    Show-CompletionMenu -Candidates $menuState.Candidates -Filter $menuState.Filter -SelectedIndex $menuState.SelectedIndex -MaxVisibleRows $maxVisible
                }
            } elseif ($key.Key -eq 'DownArrow') {
                if ($script:UseMenu -and $menuState -and $menuState.Candidates.Count -gt 0) {
                    $menuState.SelectedIndex = ($menuState.SelectedIndex + 1) % $menuState.Candidates.Count
                    Show-CompletionMenu -Candidates $menuState.Candidates -Filter $menuState.Filter -SelectedIndex $menuState.SelectedIndex -MaxVisibleRows $maxVisible
                }
            } elseif ($key.Key -eq 'Escape') {
                if ($script:UseMenu -and $menuState) {
                    Hide-CompletionMenu -TotalRows $script:MenuTotalRows
                    $menuSuppressed = $true
                    $menuSuppressedFilter = if ($buffer.ToString() -match '^/stop\s+(.*)$') { $Matches[1] } else { '' }
                    $menuState = $null
                }
            } elseif (-not [char]::IsControl($key.KeyChar)) {
                [void]$buffer.Append($key.KeyChar)
                Write-Host -NoNewline $key.KeyChar
            }

            # Skip the shared recompute below for the keys that already fully
            # handled their own redraw above - re-running it for those would
            # immediately recompute a fresh $menuState (Index reset to 0) and
            # stomp on the Up/Down/Tab selection that was just made.
            $skipRecompute = ($key.Key -in @('UpArrow', 'DownArrow', 'Escape')) -or ($script:UseMenu -and $key.Key -eq 'Tab')

            if (-not $skipRecompute) {
                if ($buffer.ToString() -match '^/stop\s+(.*)$') {
                    $typed = $Matches[1]
                    if ($script:UseMenu) {
                        if ($menuSuppressed -and $typed -eq $menuSuppressedFilter) {
                            # Escape was just pressed for this exact fragment -
                            # stay hidden until the user actually changes it.
                        } else {
                            $menuSuppressed = $false
                            $candidates = Get-StopCandidates -Typed $typed
                            if ($candidates.Count -eq 0) {
                                if ($menuState) { Hide-CompletionMenu -TotalRows $script:MenuTotalRows }
                                $menuState = $null
                            } else {
                                $menuState = [PSCustomObject]@{ Candidates = $candidates; Filter = $typed; SelectedIndex = 0 }
                                Show-CompletionMenu -Candidates $candidates -Filter $typed -SelectedIndex 0 -MaxVisibleRows $maxVisible
                            }
                        }
                    } elseif ($tabState) {
                        if ($tabState.Candidates.Count -gt 1) {
                            $overlayLen = Write-InlineOverlay -Text (" ({0}/{1})" -f ($tabState.Index + 1), $tabState.Candidates.Count)
                        }
                    } elseif ($typed) {
                        $candidates = Get-StopCandidates -Typed $typed
                        if ($candidates.Count -gt 0 -and $candidates[0].Length -gt $typed.Length) {
                            $overlayLen = Write-InlineOverlay -Text $candidates[0].Substring($typed.Length)
                        }
                    }
                } elseif ($script:UseMenu -and $menuState) {
                    Hide-CompletionMenu -TotalRows $script:MenuTotalRows
                    $menuState = $null
                    $menuSuppressed = $false
                }
            }
            continue
        }

        # Keep this sleep short so typing stays responsive - a 150ms poll
        # here made every keystroke feel laggy. The queue pump itself (which
        # enumerates all processes) only needs to run every couple seconds,
        # not on every idle tick, so it's throttled separately below.
        Start-Sleep -Milliseconds 25
        if (((Get-Date) - $lastPump).TotalMilliseconds -lt 2000) { continue }
        $lastPump = Get-Date

        # Mirrors Invoke-QueuePump's own guard so the menu is only hidden
        # when a queued mirror is actually about to print output through it -
        # avoids a needless hide/reshow flicker on every idle poll tick.
        $queuePumpWillRun = $script:MirrorQueue.Count -gt 0 -and -not (Test-MirrorActive)
        if ($queuePumpWillRun -and $script:UseMenu -and $menuState) {
            Hide-CompletionMenu -TotalRows $script:MenuTotalRows
        }

        $before = $script:MirrorQueue.Count
        Invoke-QueuePump
        if ($script:MirrorQueue.Count -lt $before) {
            # A queued mirror just started - redraw the prompt line so the
            # user's partially-typed input isn't lost underneath the output.
            Clear-InlineOverlay -Length $overlayLen
            Write-Host ""
            Show-Prompt -CurrentText $buffer.ToString()
            $overlayLen = 0
        }

        if ($queuePumpWillRun -and $script:UseMenu -and $menuState) {
            Show-CompletionMenu -Candidates $menuState.Candidates -Filter $menuState.Filter -SelectedIndex $menuState.SelectedIndex -MaxVisibleRows $maxVisible
        }
    }
}
