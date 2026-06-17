<#
.SYNOPSIS
    Smarter attention flow for claude-herald.
    Wait silently -> "are you there" push -> silence local until ntfy reply.
#>
param([string]$Event = "input")

$root         = Split-Path $PSScriptRoot -Parent
$configPath   = Join-Path $root "config.json"
$sentinelFile = Join-Path $root ".herald-alert"
$awayFile     = Join-Path $root ".herald-away"
$playScript   = Join-Path $root "engine\play.ps1"

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
    if (-not $config.mobile.enabled -or -not $config.mobile.ntfy_topic) { return }
    $replyUrl = "$($config.mobile.ntfy_server)/$($config.mobile.reply_topic)"
    $hdrs = @{
        "Title"   = "Claude - Are you there, $name?"
        "Tags"    = "wave,clock2"
        "Actions" = "http, Yes I am, $replyUrl, method=POST, body=yes; http, Give me a minute, $replyUrl, method=POST, body=later"
    }
    if ($config.mobile.ntfy_token) { $hdrs["Authorization"] = "Bearer $($config.mobile.ntfy_token)" }
    try {
        Invoke-RestMethod -Uri "$($config.mobile.ntfy_server)/$($config.mobile.ntfy_topic)" `
            -Method Post -Body "Still here with something for you." `
            -Headers $hdrs -ErrorAction Stop | Out-Null
    } catch { }
}

function Wait-ForNtfyReply {
    $server     = $config.mobile.ntfy_server
    $replyTopic = $config.mobile.reply_topic
    $hdrs = @{}
    if ($config.mobile.ntfy_token) { $hdrs["Authorization"] = "Bearer $($config.mobile.ntfy_token)" }
    $since = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    while (Test-Path $sentinelFile) {
        Start-Sleep -Seconds 5
        if (-not (Test-Path $sentinelFile)) { return "user-typed" }
        try {
            $resp = Invoke-WebRequest -Uri "$server/$replyTopic/json?poll=1&since=$since" `
                -Headers $hdrs -UseBasicParsing -ErrorAction Stop
            $msgs = $resp.Content -split "`n" | Where-Object { $_.Trim() } | ForEach-Object {
                try { $_ | ConvertFrom-Json } catch { $null }
            } | Where-Object { $_ -and $_.event -eq "message" }
            foreach ($msg in $msgs) {
                $since = $msg.time + 1
                $text  = $msg.message.Trim().ToLower()
                if ($text -in @("yes","y","yep","yeah","yes i am","im here","i'm here")) { return "yes" }
                if ($text -in @("no","n","later","give me a minute","busy","in a bit"))   { return "later" }
            }
        } catch { }
    }
    return "user-typed"
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

# Phase 3: silent - wait for ntfy only
$PID | Set-Content $awayFile -Force

$result = Wait-ForNtfyReply

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
