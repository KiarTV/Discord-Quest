# Regenerates mirror.ps1 by concatenating the modular sources under src/.
# Run this after any change under src/, then commit both the src change and
# the regenerated mirror.ps1 - the raw GitHub URL people `irm | iex` points
# at the committed mirror.ps1, not at src/, so an unbuilt mirror.ps1 is a
# shipped bug. See CLAUDE.md for the module layout and load order.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Order matters: param() must lead the file (only comments may precede it),
# and every function must be defined before Main.Driver.ps1's driver code
# at the bottom calls it.
$files = @(
    'src/Main.Params.ps1'
    'src/Common/UI.ps1'
    'src/Common/PlatformDispatch.ps1'
    'src/Platform/Windows.ps1'
    'src/Platform/MacOS.ps1'
    'src/Common/Discovery.ps1'
    'src/Common/Queue.ps1'
    'src/Common/InputLoop.ps1'
    'src/Main.Driver.ps1'
)

$header = @'
# =============================================================================
# GENERATED FILE - do not edit directly.
# Source lives in src/ - run .\build.ps1 to regenerate this file, then
# commit both. See CLAUDE.md for the module layout.
# =============================================================================

'@

$parts = foreach ($f in $files) {
    $path = Join-Path $root $f
    if (-not (Test-Path $path)) { throw "Missing source file: $f" }
    $marker = "# --- $f " + ('-' * [Math]::Max(1, 70 - $f.Length))
    $marker + "`n" + (Get-Content $path -Raw).TrimEnd()
}

$output = $header + ($parts -join "`n`n") + "`n"
Set-Content -Path (Join-Path $root 'mirror.ps1') -Value $output -NoNewline -Encoding utf8

Write-Host "Built mirror.ps1 from $($files.Count) source files."
