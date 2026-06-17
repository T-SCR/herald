<#
.SYNOPSIS
    Smarter attention flow for claude-herald.
    Wait silently -> "are you there" Telegram push -> wait for snooze or user response.
#>
param([string]$Event = "input")

$root         = Split-Path $PSScriptRoot -Parent
$configPath   = Join-Path $root "config.json"
$sentinelFile = Join-Path $root ".herald-alert"
$awayFile     = Join-Path $root ".herald-away"
$snoozeFile   = Join-Path $root ".herald-snooze"
$playScript   = Join-Path $root "engine\play.ps1"
$pushScript   = Join-Path $root "engine\push.ps1"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled) { exit 0 }

$name  = if ($config.tone.mode -eq "sir") { "sir" } else { $config.tone.name }
$waitS = [int]$config.alerts.attention_wait_seconds

function Invoke-InputSound {
    $packName = $config.audio.active_pack
    $packDir  = Join-Path $root "sounds\$packName"
    $mPath    = Join-Path $packDir "openpeon.json"
    if (-not (Test-Path $mPath)) { return }
    $manifest = Get-Content $mPath -Raw | ConvertFrom-Json
    $catProp  = $manifest.categories.PSObject.Properties |
                Where-Object { $_.Name -eq "input.required" } | Select-Object -First 1
    if (-not $catProp) { return }
    $files = $catProp.Value.sounds
    $pick  = $files[(Get-Random -Maximum $files.Count)]
    $fPath = Join-Path $packDir "sounds\$(Split-Path $pick.file -Leaf)"
    if ((Test-Path $fPath) -and $config.audio.enabled) {
        & $playScript -Path $fPath -Volume ([double]$config.audio.volume)
    }
}

function Invoke-AreYouTherePush {
    & $pushScript -Title "Claude - Are you there, $name?" `
        -Body "Still here with something for you. Tap Snooze if you need a few minutes." `
        -Priority "default"
}

function Wait-ForReply {
    # Watch sentinel + snooze file. reply-listener.ps1 handles the actual Telegram polling.
    $elapsed = 0
    $maxWait = 600  # 10 min max before giving up
    while ((Test-Path $sentinelFile) -and $elapsed -lt $maxWait) {
        Start-Sleep -Seconds 3
        $elapsed += 3
        if (Test-Path $snoozeFile) {
            Remove-Item $snoozeFile -Force -ErrorAction SilentlyContinue
            return "later"
        }
    }
    return if (Test-Path $sentinelFile) { "timeout" } else { "user-typed" }
}

# Write sentinel
$PID | Set-Content $sentinelFile -Force

# Phase 1: silent wait
Start-Sleep -Seconds $waitS
if (-not (Test-Path $sentinelFile)) { exit 0 }

# Phase 2: one local sound + push
Invoke-InputSound
if ($config.notify.terminal) {
    Write-Host "  [!] claude  Are you there, $name? Still here with something for you." -ForegroundColor Yellow
}
Invoke-AreYouTherePush

# Phase 3: wait for reply-listener to signal (paste to terminal = sentinel cleared; snooze = snooze file)
$PID | Set-Content $awayFile -Force
$result = Wait-ForReply
[System.IO.File]::Delete($awayFile)

if ($result -eq "yes" -and (Test-Path $sentinelFile)) {
    if ($config.notify.terminal) {
        Write-Host "  [+] claude  Welcome back, $name." -ForegroundColor Green
    }
    Invoke-InputSound
    Start-Sleep -Seconds $waitS
    if (Test-Path $sentinelFile) {
        Invoke-AreYouTherePush
    }
}
