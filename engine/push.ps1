<#
.SYNOPSIS
    Mobile push via Telegram Bot API with inline keyboard buttons for two-way replies.
    Automatically chunks messages > 3800 chars across multiple Telegram messages.
#>
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Body,
    [ValidateSet("min","low","default","high","urgent")][string]$Priority = "default"
)

$root       = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "config.json"
if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.mobile.enabled) { exit 0 }

$token  = $config.mobile.telegram_bot_token
$chatId = $config.mobile.telegram_chat_id
if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) { exit 0 }

$baseUrl  = "https://api.telegram.org/bot$token"
$maxChunk = 3800

# Build inline keyboard JSON based on event type (attached to last chunk only)
$keyboard = $null
if ($Title -match "Authorization|Permission") {
    $keyboard = '{"inline_keyboard":[[{"text":"Approve","callback_data":"yes"},{"text":"Deny","callback_data":"no"}]]}'
} elseif ($Title -match "Question|Input|Waiting") {
    $keyboard = '{"inline_keyboard":[[{"text":"Yes","callback_data":"yes"},{"text":"No","callback_data":"no"},{"text":"Snooze","callback_data":"later"}]]}'
} elseif ($Title -match "Done") {
    $keyboard = '{"inline_keyboard":[[{"text":"Reply","callback_data":"reply"}]]}'
}

function Send-TelegramMessage([string]$Text, [string]$KeyboardJson = $null) {
    $payload = (@{ chat_id = $chatId; text = $Text } | ConvertTo-Json -Compress)
    if ($KeyboardJson) {
        $payload = $payload.TrimEnd('}') + ',"reply_markup":' + $KeyboardJson + '}'
    }
    foreach ($attempt in 1..2) {
        try {
            Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method Post `
                -Body $payload -ContentType "application/json" -ErrorAction Stop | Out-Null
            return $true
        } catch {
            if ($attempt -eq 2) { $_ | Out-File (Join-Path $root "herald.log") -Append }
            else { Start-Sleep -Seconds 6 }
        }
    }
    return $false
}

# Build full text and split into chunks
$fullText = "[$Title]`n`n$Body"
$chunks   = [System.Collections.Generic.List[string]]::new()

if ($fullText.Length -le $maxChunk) {
    $chunks.Add($fullText)
} else {
    $remaining = $fullText
    while ($remaining.Length -gt $maxChunk) {
        # Break at last newline within chunk to avoid mid-word splits
        $slice    = $remaining.Substring(0, $maxChunk)
        $lastNL   = $slice.LastIndexOf("`n")
        $breakAt  = if ($lastNL -gt 200) { $lastNL } else { $maxChunk }
        $chunks.Add($remaining.Substring(0, $breakAt))
        $remaining = $remaining.Substring($breakAt).TrimStart("`n")
    }
    if ($remaining) { $chunks.Add($remaining) }
}

# Send chunks — keyboard on last chunk only
for ($i = 0; $i -lt $chunks.Count; $i++) {
    $isLast = ($i -eq $chunks.Count - 1)
    $kb     = if ($isLast) { $keyboard } else { $null }
    Send-TelegramMessage $chunks[$i] $kb | Out-Null
}

# Ensure reply listener is running
$pidFile        = Join-Path $root ".reply-listener-pid"
$listenerScript = Join-Path $root "engine\reply-listener.ps1"
$isRunning      = $false
if (Test-Path $pidFile) {
    $savedPid = (Get-Content $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($savedPid -and (Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue)) {
        $isRunning = $true
    }
}
if (-not $isRunning) {
    Start-Process powershell -WindowStyle Hidden -ArgumentList @(
        "-NoProfile", "-NonInteractive",
        "-File", "`"$listenerScript`""
    )
}
