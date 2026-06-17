<#
.SYNOPSIS
    Claude Code Stop hook handler.
    Fires when Claude finishes a turn and is waiting for user input.
    Reads hook payload from stdin, classifies the stop reason, speaks and notifies.
#>

$root       = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "config.json"
$linesPath  = Join-Path $root "voice\lines.json"
$speakScript = Join-Path $root "engine\speak.ps1"
$toastScript = Join-Path $root "engine\toast.ps1"
$pushScript  = Join-Path $root "engine\push.ps1"

if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled) { exit 0 }

$lines = Get-Content $linesPath -Raw | ConvertFrom-Json

# Read hook payload from stdin
$payload = $null
try {
    $raw = $input | Out-String
    if ($raw.Trim()) { $payload = $raw | ConvertFrom-Json }
} catch { }

# Classify stop reason by inspecting the last assistant message
$stopReason  = "task_complete"
$lastMessage = ""

try {
    if ($payload -and $payload.transcript_path -and (Test-Path $payload.transcript_path)) {
        $transcript = Get-Content $payload.transcript_path -Raw | ConvertFrom-Json
        $messages   = $transcript.messages
        # Walk back to find last assistant message
        for ($i = $messages.Count - 1; $i -ge 0; $i--) {
            if ($messages[$i].role -eq "assistant") {
                $lastMessage = ($messages[$i].content | Where-Object { $_.type -eq "text" } | Select-Object -Last 1).text
                break
            }
        }
    }
} catch { }

# Heuristic classification
if ($lastMessage -match '\?\s*$') {
    $stopReason = "question"
} elseif ($lastMessage -match '(?i)(permission|allow|approve|authorize|confirm|deny|block)') {
    $stopReason = "permission_needed"
} elseif ($lastMessage -match '(?i)(need|require|waiting|please|input|respond|clarif)') {
    $stopReason = "needs_input"
} else {
    $stopReason = "task_complete"
}

# Pick a random line from the pool
$pool = $lines.stop.$stopReason
$message = $pool[(Get-Random -Maximum $pool.Count)]

# Build notification content
$toastTitle = switch ($stopReason) {
    "task_complete"      { "Claude — Done" }
    "needs_input"        { "Claude — Needs Input" }
    "permission_needed"  { "Claude — Authorization Required" }
    "question"           { "Claude — Question" }
    default              { "Claude — Attention" }
}

# Speak
if ($config.hooks.on_stop) {
    & $speakScript -Message $message -Priority "normal"
}

# Toast
& $toastScript -Title $toastTitle -Body $message

# Mobile push — only for permission/input states (don't spam every task completion)
if ($stopReason -in @("permission_needed", "needs_input", "question")) {
    $pushPriority = if ($stopReason -eq "permission_needed") { "high" } else { "default" }
    & $pushScript -Title $toastTitle -Body $message -Priority $pushPriority
} elseif ($config.mobile.push_on_complete) {
    & $pushScript -Title $toastTitle -Body $message -Priority "low"
}
