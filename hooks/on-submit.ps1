<#
.SYNOPSIS
    UserPromptSubmit hook - clears attention state, plays acknowledge sound
    when returning from an attention/away state.
#>
$root         = Split-Path $PSScriptRoot -Parent
$configPath   = Join-Path $root "config.json"
$sentinelFile = Join-Path $root ".herald-alert"
$awayFile     = Join-Path $root ".herald-away"
$playScript   = Join-Path $root "engine\play.ps1"

$wasAttention = (Test-Path $sentinelFile) -or (Test-Path $awayFile)

[System.IO.File]::Delete($sentinelFile)
[System.IO.File]::Delete($awayFile)

# Play acknowledge sound only when returning from attention/away state
if ($wasAttention -and (Test-Path $configPath)) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($config.enabled -and $config.audio.enabled) {
        $packName = $config.audio.active_pack
        $packDir  = Join-Path $root "sounds\$packName"
        $mPath    = Join-Path $packDir "openpeon.json"
        if (Test-Path $mPath) {
            $manifest = Get-Content $mPath -Raw | ConvertFrom-Json
            $catProp  = $manifest.categories.PSObject.Properties |
                        Where-Object { $_.Name -eq "task.acknowledge" } | Select-Object -First 1
            if ($catProp -and $catProp.Value.sounds.Count -gt 0) {
                $files = $catProp.Value.sounds
                $pick  = $files[(Get-Random -Maximum $files.Count)]
                $fPath = Join-Path $packDir "sounds\$(Split-Path $pick.file -Leaf)"
                if (Test-Path $fPath) {
                    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
                        "-NoProfile","-NonInteractive",
                        "-File","`"$playScript`"",
                        "-Path","`"$fPath`"",
                        "-Volume",([double]$config.audio.volume)
                    )
                }
            }
        }
        $name = if ($config.tone.mode -eq "sir") { "sir" } else { $config.tone.name }
        if ($config.notify.terminal) {
            Write-Host "  [>] claude  Received, $name." -ForegroundColor Cyan
        }
    }
}

# Pass through
