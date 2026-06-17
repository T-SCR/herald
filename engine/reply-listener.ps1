<#
.SYNOPSIS
    Background reply listener for claude-herald.
    Polls Telegram Bot API for messages/button taps, then auto-pastes into the active terminal.
    "later"/"snooze" callbacks write .herald-snooze (no paste) so repeat-alert can exit cleanly.
#>

$root       = Split-Path $PSScriptRoot -Parent
$configPath = Join-Path $root "config.json"
$logPath    = Join-Path $root "herald.log"

if (-not (Test-Path $configPath)) { exit 0 }
$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.mobile.enabled) { exit 0 }

# Bridge takes over Telegram polling when running — don't conflict
$bridgePid = Join-Path $root ".bridge-pid"
if (Test-Path $bridgePid) {
    $bpid = (Get-Content $bridgePid -Raw -ErrorAction SilentlyContinue).Trim()
    if ($bpid -and (Get-Process -Id ([int]$bpid) -ErrorAction SilentlyContinue)) { exit 0 }
}

$token  = $config.mobile.telegram_bot_token
$chatId = [string]$config.mobile.telegram_chat_id
if ([string]::IsNullOrWhiteSpace($token) -or [string]::IsNullOrWhiteSpace($chatId)) { exit 0 }

$baseUrl = "https://api.telegram.org/bot$token"

# Windows API for window focus and SendKeys
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
Add-Type -AssemblyName System.Windows.Forms

function Send-ToTerminal([string]$Text) {
    $targets = @("WindowsTerminal","claude","powershell","bash")
    $win = $null
    foreach ($t in $targets) {
        $proc = Get-Process | Where-Object {
            $_.MainWindowHandle -ne 0 -and ($_.Name -match $t -or $_.MainWindowTitle -match $t)
        } | Select-Object -First 1
        if ($proc) { $win = $proc; break }
    }
    if ($win) {
        [WinFocus]::ShowWindow($win.MainWindowHandle, 9) | Out-Null
        [WinFocus]::SetForegroundWindow($win.MainWindowHandle) | Out-Null
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Clipboard]::SetText($Text)
        [System.Windows.Forms.SendKeys]::SendWait("^v")
        Start-Sleep -Milliseconds 150
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        return $true
    }
    return $false
}

function Answer-Callback([string]$CallbackId, [string]$Message = "Got it") {
    try {
        $body = @{ callback_query_id = $CallbackId; text = $Message } | ConvertTo-Json -Compress
        Invoke-RestMethod -Uri "$baseUrl/answerCallbackQuery" -Method Post `
            -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null
    } catch { }
}

# Write PID for health checks
$PID | Set-Content (Join-Path $root ".reply-listener-pid") -Force

$offset = 0

while ($true) {
    try {
        $url  = "$baseUrl/getUpdates?offset=$offset&timeout=10&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D"
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 15 -ErrorAction Stop

        foreach ($update in $resp.result) {
            $offset = $update.update_id + 1
            $text   = $null

            if ($update.callback_query) {
                $cq = $update.callback_query
                if ([string]$cq.message.chat.id -eq $chatId) {
                    $text = $cq.data.Trim().ToLower()
                    Answer-Callback $cq.id
                }
            } elseif ($update.message -and $update.message.text) {
                if ([string]$update.message.chat.id -eq $chatId) {
                    $text = $update.message.text.Trim()
                }
            }

            if (-not $text) { continue }

            # Normalise shorthand
            $normalised = switch ($text.ToLower()) {
                "yes"     { "yes" }
                "y"       { "yes" }
                "approve" { "yes" }
                "no"      { "no" }
                "n"       { "no" }
                "deny"    { "no" }
                "ok"      { "ok" }
                "later"   { "later" }
                "snooze"  { "later" }
                default   { $text }
            }

            if ($normalised -eq "later") {
                # Signal repeat-alert to stop pestering — do NOT paste to terminal
                "" | Set-Content (Join-Path $root ".herald-snooze") -Force
                Add-Content $logPath "[$(Get-Date -f 'HH:mm:ss')] telegram: snooze received"
            } else {
                $pasted = Send-ToTerminal $normalised
                Add-Content $logPath "[$(Get-Date -f 'HH:mm:ss')] telegram: '$normalised' pasted=$pasted"
            }
        }
    } catch {
        # Telegram unreachable — back off and retry
        Start-Sleep -Seconds 8
    }
}
