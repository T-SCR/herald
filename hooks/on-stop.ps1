<#
.SYNOPSIS
    Claude Code Stop hook.
    Home mode: sound + banner + push on attention events only.
    Away mode: push Claude's actual response to Telegram for every stop — creates a
               two-way conversation loop (user replies in Telegram, reply-listener
               pastes the reply back into the Claude terminal).
#>

$root         = Split-Path $PSScriptRoot -Parent
$configPath   = Join-Path $root "config.json"
$linesPath    = Join-Path $root "voice\lines.json"
$notifyScript = Join-Path $root "engine\notify.ps1"
$repeatScript = Join-Path $root "engine\repeat-alert.ps1"
$pushScript   = Join-Path $root "engine\push.ps1"
$sentinelFile = Join-Path $root ".herald-alert"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled)       { exit 0 }
if (-not $config.hooks.on_stop) { exit 0 }

$lines    = Get-Content $linesPath -Raw | ConvertFrom-Json
$awayMode = [bool]$config.away_mode
$name     = if ($config.tone.mode -eq "sir") { "sir" } else { $config.tone.name }

# Clear any existing repeat alert
[System.IO.File]::Delete($sentinelFile)
[System.IO.File]::Delete((Join-Path $root ".herald-away"))

# Read hook payload and extract last assistant message
$payload     = $null
$lastMessage = ""

try {
    $raw = $input | Out-String
    if ($raw.Trim()) { $payload = $raw | ConvertFrom-Json }
} catch { }

try {
    if ($payload -and $payload.transcript_path -and (Test-Path $payload.transcript_path)) {
        $transcript = Get-Content $payload.transcript_path -Raw | ConvertFrom-Json
        $messages   = $transcript.messages
        for ($i = $messages.Count - 1; $i -ge 0; $i--) {
            if ($messages[$i].role -eq "assistant") {
                $lastMessage = ($messages[$i].content |
                    Where-Object { $_.type -eq "text" } | Select-Object -Last 1).text
                break
            }
        }
    }
} catch { }

# Classify stop reason
$stopReason = if ($lastMessage -match '\?\s*$') {
    "question"
} elseif ($lastMessage -match '(?i)(permission|allow|approve|authorize|confirm|deny|block)') {
    "permission"
} elseif ($lastMessage -match '(?i)(need|require|waiting|please|input|respond|clarif)') {
    "input"
} else {
    "done"
}

$lineKey = switch ($stopReason) {
    "done"       { "task_complete" }
    "question"   { "question" }
    "permission" { "permission_needed" }
    "input"      { "needs_input" }
    default      { "task_complete" }
}
$pool         = $lines.stop.$lineKey
$voiceLine    = $pool[(Get-Random -Maximum $pool.Count)]

$attentionEvents = @("permission", "question", "input")

if ($awayMode) {
    # AWAY MODE: push Claude's actual response to Telegram — no local sound/banner.
    # push.ps1 handles chunking for long messages. User can reply in Telegram to continue.
    $priority = switch ($stopReason) {
        "permission" { "high" }
        "question"   { "default" }
        "input"      { "default" }
        "done"       { "low" }
        default      { "low" }
    }
    $pushTitle = switch ($stopReason) {
        "done"       { "Claude - Done" }
        "question"   { "Claude - Question for you" }
        "permission" { "Claude - Authorization Required" }
        "input"      { "Claude - Needs your input" }
        default      { "Claude" }
    }
    $pushBody = if ($lastMessage) { $lastMessage.Trim() } else { $voiceLine }
    & $pushScript -Title $pushTitle -Body $pushBody -Priority $priority

    # Start are-you-there attention flow for events that need a response
    if ($stopReason -in $attentionEvents -and $config.alerts.repeat_enabled) {
        Start-Process powershell -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-NonInteractive",
            "-File", "`"$repeatScript`"",
            "-Event", $stopReason
        )
    }
} else {
    # HOME MODE: local sound + banner, push to phone only on attention events
    & $notifyScript -Event $stopReason -Message $voiceLine

    if ($stopReason -in $attentionEvents -and $config.alerts.repeat_enabled) {
        Start-Process powershell -WindowStyle Hidden -ArgumentList @(
            "-NoProfile", "-NonInteractive",
            "-File", "`"$repeatScript`"",
            "-Event", $stopReason
        )
    } elseif ($config.mobile.push_on_complete) {
        & $pushScript -Title "Claude - Done" -Body $voiceLine -Priority "low"
    }
}
