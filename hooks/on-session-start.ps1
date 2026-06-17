<#
.SYNOPSIS
    SessionStart hook - plays JARVIS session.start sound when Claude Code opens.
#>
$root         = "C:\Users\tscr\tools\claude-herald"
$configPath   = Join-Path $root "config.json"
$notifyScript = Join-Path $root "engine\notify.ps1"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled) { exit 0 }

# Play session.start sound directly (not via notify.ps1 event system)
if ($config.audio.enabled) {
    $packName   = $config.audio.active_pack
    $packDir    = Join-Path $root "sounds\$packName"
    $manifestP  = Join-Path $packDir "openpeon.json"
    $playScript = Join-Path $root "engine\play.ps1"

    if (Test-Path $manifestP) {
        $manifest  = Get-Content $manifestP -Raw | ConvertFrom-Json
        $catSounds = $manifest.categories.PSObject.Properties |
                     Where-Object { $_.Name -eq "session.start" } |
                     Select-Object -First 1

        if ($catSounds -and $catSounds.Value.sounds.Count -gt 0) {
            $soundFiles = $catSounds.Value.sounds
            $pick       = $soundFiles[(Get-Random -Maximum $soundFiles.Count)]
            $fileName   = Split-Path $pick.file -Leaf
            $filePath   = Join-Path $packDir "sounds\$fileName"

            if (Test-Path $filePath) {
                Start-Process powershell -WindowStyle Hidden -ArgumentList @(
                    "-NoProfile", "-NonInteractive",
                    "-File", "`"$playScript`"",
                    "-Path", "`"$filePath`"",
                    "-Volume", ([double]$config.audio.volume)
                )
            }
        }
    }
}

# Pass through - do not block session