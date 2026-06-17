<#
.SYNOPSIS
    claude-herald CLI — manage your voice notification settings.
.DESCRIPTION
    Toggle features on/off, test voice, check status, list available voices.

.EXAMPLE
    .\herald.ps1 --status
    .\herald.ps1 --toggle voice
    .\herald.ps1 --toggle toast
    .\herald.ps1 --toggle mobile
    .\herald.ps1 --toggle tool-events
    .\herald.ps1 --toggle complete-push
    .\herald.ps1 --test
    .\herald.ps1 --set-topic my-unique-topic-123
    .\herald.ps1 --voices
    .\herald.ps1 --set-voice "Microsoft Zira Desktop"
    .\herald.ps1 --mute
    .\herald.ps1 --unmute
#>

param(
    [switch]$Status,
    [string]$Toggle,
    [switch]$Test,
    [string]$SetTopic,
    [string]$SetVoice,
    [switch]$Voices,
    [switch]$Mute,
    [switch]$Unmute,
    [switch]$Help
)

$configPath = Join-Path $PSScriptRoot "config.json"

function Get-Config {
    Get-Content $configPath -Raw | ConvertFrom-Json
}

function Save-Config($cfg) {
    $cfg | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
}

function Write-Status($label, $value) {
    $icon = if ($value) { "[ON] " } else { "[OFF]" }
    $color = if ($value) { "Green" } else { "DarkGray" }
    Write-Host "  $icon  $label" -ForegroundColor $color
}

if ($Help -or (-not ($Status -or $Toggle -or $Test -or $SetTopic -or $SetVoice -or $Voices -or $Mute -or $Unmute))) {
    Write-Host ""
    Write-Host "claude-herald" -ForegroundColor Cyan
    Write-Host "Voice + notification bridge for Claude Code" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\herald.ps1 --status                     Show current config"
    Write-Host "  .\herald.ps1 --toggle <feature>           Toggle a feature on/off"
    Write-Host "  .\herald.ps1 --test                       Speak a test line"
    Write-Host "  .\herald.ps1 --mute / --unmute            Quick mute toggle"
    Write-Host "  .\herald.ps1 --voices                     List installed TTS voices"
    Write-Host "  .\herald.ps1 --set-voice <name>           Switch TTS voice"
    Write-Host "  .\herald.ps1 --set-topic <ntfy-topic>     Set mobile push topic"
    Write-Host ""
    Write-Host "Toggleable features:" -ForegroundColor Yellow
    Write-Host "  voice         Voice TTS on/off"
    Write-Host "  toast         Windows toast notifications"
    Write-Host "  mobile        Mobile push via ntfy.sh"
    Write-Host "  tool-events   Per-tool announcements (Write/Edit/Bash)"
    Write-Host "  complete-push Push to phone even on task-complete (not just attention)"
    Write-Host "  tool-details  Include filename/command in announcements"
    Write-Host ""
    exit 0
}

if ($Status) {
    $cfg = Get-Config
    Write-Host ""
    Write-Host "claude-herald status" -ForegroundColor Cyan
    Write-Host "--------------------" -ForegroundColor DarkGray
    Write-Status "Master switch        " $cfg.enabled
    Write-Status "Voice TTS            " $cfg.voice.enabled
    Write-Status "Toast notifications  " $cfg.toast.enabled
    Write-Status "Toast on tool events " $cfg.toast.show_tool_events
    Write-Status "On-stop hook         " $cfg.hooks.on_stop
    Write-Status "On-tool-use hook     " $cfg.hooks.on_tool_use
    Write-Status "Mobile push (ntfy)   " $cfg.mobile.enabled
    Write-Status "Push on complete     " $cfg.mobile.push_on_complete
    Write-Status "Tool details in TTS  " $cfg.announcements.tool_details
    Write-Host ""
    Write-Host "  Voice : $($cfg.voice.name)  rate=$($cfg.voice.rate)  vol=$($cfg.voice.volume)" -ForegroundColor DarkGray
    $topicDisplay = if ($cfg.mobile.ntfy_topic) { $cfg.mobile.ntfy_topic } else { "(not set)" }
    Write-Host "  ntfy  : $($cfg.mobile.ntfy_server)/$topicDisplay" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

if ($Mute) {
    $cfg = Get-Config
    $cfg.voice.enabled = $false
    Save-Config $cfg
    Write-Host "Voice muted." -ForegroundColor Yellow
    exit 0
}

if ($Unmute) {
    $cfg = Get-Config
    $cfg.voice.enabled = $true
    Save-Config $cfg
    Write-Host "Voice unmuted." -ForegroundColor Green
    exit 0
}

if ($Toggle) {
    $cfg = Get-Config
    switch ($Toggle.ToLower()) {
        "voice"         { $cfg.voice.enabled                = -not $cfg.voice.enabled;                $label = "Voice TTS" }
        "toast"         { $cfg.toast.enabled                = -not $cfg.toast.enabled;                $label = "Toast notifications" }
        "mobile"        { $cfg.mobile.enabled               = -not $cfg.mobile.enabled;               $label = "Mobile push" }
        "tool-events"   { $cfg.toast.show_tool_events       = -not $cfg.toast.show_tool_events;       $label = "Toast on tool events" }
        "complete-push" { $cfg.mobile.push_on_complete      = -not $cfg.mobile.push_on_complete;      $label = "Push on task complete" }
        "tool-details"  { $cfg.announcements.tool_details   = -not $cfg.announcements.tool_details;   $label = "Tool details in TTS" }
        default {
            Write-Host "Unknown feature: $Toggle. Run --help for options." -ForegroundColor Red
            exit 1
        }
    }
    Save-Config $cfg
    $newVal = switch ($Toggle.ToLower()) {
        "voice"         { $cfg.voice.enabled }
        "toast"         { $cfg.toast.enabled }
        "mobile"        { $cfg.mobile.enabled }
        "tool-events"   { $cfg.toast.show_tool_events }
        "complete-push" { $cfg.mobile.push_on_complete }
        "tool-details"  { $cfg.announcements.tool_details }
    }
    $state = if ($newVal) { "ON" } else { "OFF" }
    $color = if ($newVal) { "Green" } else { "Yellow" }
    Write-Host "$label toggled $state." -ForegroundColor $color
    exit 0
}

if ($SetTopic) {
    $cfg = Get-Config
    $cfg.mobile.ntfy_topic = $SetTopic
    $cfg.mobile.enabled    = $true
    Save-Config $cfg
    Write-Host "Mobile topic set to: $SetTopic" -ForegroundColor Green
    Write-Host "Mobile push enabled. Subscribe on your phone at: $($cfg.mobile.ntfy_server)/$SetTopic" -ForegroundColor Cyan
    exit 0
}

if ($Voices) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    Write-Host ""
    Write-Host "Installed TTS voices:" -ForegroundColor Cyan
    $synth.GetInstalledVoices() | ForEach-Object {
        $info = $_.VoiceInfo
        Write-Host "  $($info.Name)  [$($info.Gender), $($info.Culture)]" -ForegroundColor White
    }
    $synth.Dispose()
    Write-Host ""
    exit 0
}

if ($SetVoice) {
    $cfg = Get-Config
    $cfg.voice.name = $SetVoice
    Save-Config $cfg
    Write-Host "Voice set to: $SetVoice" -ForegroundColor Green
    exit 0
}

if ($Test) {
    Write-Host "Speaking test line..." -ForegroundColor Cyan
    $speakScript = Join-Path $PSScriptRoot "engine\speak.ps1"
    & $speakScript -Message "All systems nominal. Claude Herald is online and operational."
    Write-Host "Done. If you heard nothing, run --voices to check available voices." -ForegroundColor DarkGray
    exit 0
}
