<#
.SYNOPSIS
    claude-herald CLI - manage notification settings.

.EXAMPLE
    .\herald.ps1 --status
    .\herald.ps1 --test
    .\herald.ps1 --packs
    .\herald.ps1 --set-pack peon
    .\herald.ps1 --set-pack clean_chimes
    .\herald.ps1 --set-volume 0.7
    .\herald.ps1 --toggle audio
    .\herald.ps1 --toggle terminal
    .\herald.ps1 --toggle toast
    .\herald.ps1 --toggle voice
    .\herald.ps1 --toggle mobile
    .\herald.ps1 --toggle play-on-tool
    .\herald.ps1 --mute / --unmute
    .\herald.ps1 --set-topic my-ntfy-topic
    .\herald.ps1 --voices
    .\herald.ps1 --set-profile jarvis
#>

param(
    [Alias('set-interval')][string]$SetInterval,
    [switch]$Status,
    [string]$Toggle,
    [switch]$Test,
    [switch]$Packs,
    [Alias('set-pack')][string]$SetPack,
    [Alias('set-volume')][string]$SetVolume,
    [switch]$Profiles,
    [Alias('set-profile')][string]$SetProfile,
    [Alias('set-topic')][string]$SetTopic,
    [Alias('set-voice')][string]$SetVoice,
    [switch]$Voices,
    [switch]$Mute,
    [switch]$Unmute,
    [switch]$Help
)

$configPath = Join-Path $PSScriptRoot "config.json"
function Get-Config { Get-Content $configPath -Raw | ConvertFrom-Json }
function Save-Config($cfg) { $cfg | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8 }
function Write-Status($label, $value) {
    $icon  = if ($value) { "[ON] " } else { "[OFF]" }
    $color = if ($value) { "Green" } else { "DarkGray" }
    Write-Host "  $icon  $label" -ForegroundColor $color
}

$anyFlag = $Status -or $Toggle -or $Test -or $Packs -or $SetPack -or $SetVolume `
           -or $Profiles -or $SetProfile -or $SetTopic -or $SetVoice `
           -or $Voices -or $Mute -or $Unmute

if ($Help -or (-not $anyFlag)) {
    Write-Host ""
    Write-Host "claude-herald" -ForegroundColor Cyan
    Write-Host "Notification bridge for Claude Code" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\herald.ps1 --status                   All current settings"
    Write-Host "  .\herald.ps1 --test                     Fire all 4 event types now"
    Write-Host "  .\herald.ps1 --packs                    List installed sound packs"
    Write-Host "  .\herald.ps1 --set-pack <name>          Switch active sound pack"
    Write-Host "  .\herald.ps1 --set-volume 0.0-1.0       Set audio volume"
    Write-Host "  .\herald.ps1 --toggle <feature>         Toggle on/off"
    Write-Host "  .\herald.ps1 --mute / --unmute          Quick audio mute"
    Write-Host "  .\herald.ps1 --set-topic <topic>        Enable mobile push (ntfy.sh)"
    Write-Host "  .\herald.ps1 --voices                   List installed TTS voices"
    Write-Host "  .\herald.ps1 --set-profile <name>       Switch TTS voice profile"
    Write-Host ""
    Write-Host "Toggleable features:" -ForegroundColor Yellow
    Write-Host "  audio         Sound pack playback              [default: ON]"
    Write-Host "  terminal      Styled banner in Claude terminal [default: ON]"
    Write-Host "  toast         Windows toast popups             [default: ON]"
    Write-Host "  voice         TTS voice (off by default)       [default: OFF]"
    Write-Host "  mobile        Phone push via ntfy.sh           [default: OFF]"
    Write-Host "  play-on-tool  Play sound on tool events        [default: OFF]"
    Write-Host "  tool-events   Toast on tool events"
    Write-Host "  complete-push Push to phone on task-done"
    Write-Host ""
    exit 0
}

if ($Status) {
    $cfg = Get-Config
    Write-Host ""
    Write-Host "claude-herald status" -ForegroundColor Cyan
    Write-Host "--------------------" -ForegroundColor DarkGray
    Write-Status "Master switch        " $cfg.enabled
    Write-Host ""
    Write-Host "  Audio:" -ForegroundColor DarkGray
    Write-Status "  Sound pack         " $cfg.audio.enabled
    if ($cfg.audio.enabled) {
        Write-Host "    Pack   : $($cfg.audio.active_pack)  vol=$($cfg.audio.volume)" -ForegroundColor DarkGray
    }
    Write-Status "  Play on tools      " $cfg.audio.play_on_tool
    Write-Host ""
    Write-Host "  Alerts:" -ForegroundColor DarkGray
    Write-Status "  Repeat on attention" $cfg.alerts.repeat_enabled
    if ($cfg.alerts.repeat_enabled) {
        Write-Host "    Every: $($cfg.alerts.repeat_interval_seconds)s" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Notifications:" -ForegroundColor DarkGray
    Write-Status "  Terminal banner    " $cfg.notify.terminal
    Write-Status "  Toast popups       " $cfg.toast.enabled
    Write-Status "  Toast on tools     " $cfg.toast.show_tool_events
    Write-Status "  Voice TTS          " $cfg.voice.enabled
    Write-Status "  Mobile push        " $cfg.mobile.enabled
    Write-Status "  Push on complete   " $cfg.mobile.push_on_complete
    Write-Host ""
    Write-Host "  Hooks:" -ForegroundColor DarkGray
    Write-Status "  On-stop            " $cfg.hooks.on_stop
    Write-Status "  On-tool-use        " $cfg.hooks.on_tool_use
    Write-Status "  Tool details       " $cfg.announcements.tool_details
    $topic = if ($cfg.mobile.ntfy_topic) { $cfg.mobile.ntfy_topic } else { "(not set)" }
    Write-Host "    ntfy topic: $topic" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

if ($Packs) {
    $soundsDir = Join-Path $PSScriptRoot "sounds"
    $cfg    = Get-Config
    $active = $cfg.audio.active_pack
    Write-Host ""
    Write-Host "Installed sound packs:" -ForegroundColor Cyan
    if (Test-Path $soundsDir) {
        Get-ChildItem $soundsDir -Directory | ForEach-Object {
            $mPath  = Join-Path $_.FullName "openpeon.json"
            $nFiles = (Get-ChildItem "$($_.FullName)\sounds" -File -ErrorAction SilentlyContinue).Count
            $marker = if ($_.Name -eq $active) { " [ACTIVE]" } else { "" }
            $color  = if ($_.Name -eq $active) { "Green" } else { "White" }
            $desc   = if (Test-Path $mPath) { (Get-Content $mPath -Raw | ConvertFrom-Json).display_name } else { "" }
            Write-Host "  $($_.Name)$marker" -ForegroundColor $color -NoNewline
            if ($desc) { Write-Host " - $desc ($nFiles files)" -ForegroundColor DarkGray }
            else       { Write-Host " ($nFiles files)" -ForegroundColor DarkGray }
        }
    } else { Write-Host "  None installed yet." -ForegroundColor DarkGray }
    Write-Host ""
    Write-Host "Download more : .\install-sounds.ps1 -List" -ForegroundColor DarkGray
    Write-Host "Switch pack   : .\herald.ps1 --set-pack <name>" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

if ($SetPack) {
    $cfg     = Get-Config
    $packDir = Join-Path $PSScriptRoot "sounds\$SetPack"
    if (-not (Test-Path $packDir)) {
        Write-Host "Pack '$SetPack' not found. Run: .\install-sounds.ps1 -Packs $SetPack" -ForegroundColor Red
        exit 1
    }
    $cfg.audio.active_pack = $SetPack
    Save-Config $cfg
    Write-Host "Active pack set to: $SetPack" -ForegroundColor Green
    exit 0
}

if ($SetVolume) {
    $v = [double]$SetVolume
    if ($v -lt 0 -or $v -gt 1) { Write-Host "Volume must be between 0.0 and 1.0" -ForegroundColor Red; exit 1 }
    $cfg = Get-Config
    $cfg.audio.volume = $v
    Save-Config $cfg
    Write-Host "Volume set to $v" -ForegroundColor Green
    exit 0
}

if ($Profiles) {
    $cfg    = Get-Config
    $active = $cfg.voice.active_profile
    Write-Host ""
    Write-Host "TTS voice profiles (voice is currently $(if ($cfg.voice.enabled) {'ON'} else {'OFF'})):" -ForegroundColor Cyan
    $cfg.profiles.PSObject.Properties | ForEach-Object {
        $marker = if ($_.Name -eq $active) { " [ACTIVE]" } else { "" }
        $color  = if ($_.Name -eq $active) { "Green" } else { "White" }
        Write-Host "  $($_.Name)$marker" -ForegroundColor $color -NoNewline
        Write-Host "  $($_.Value.description)  rate=$($_.Value.rate)  vol=$($_.Value.volume)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "Enable voice: .\herald.ps1 --toggle voice" -ForegroundColor Yellow
    exit 0
}

if ($SetProfile) {
    $cfg = Get-Config
    if (-not ($cfg.PSObject.Properties["profiles"] -and $cfg.profiles.PSObject.Properties[$SetProfile])) {
        $avail = ($cfg.profiles.PSObject.Properties | ForEach-Object { $_.Name }) -join ", "
        Write-Host "Profile '$SetProfile' not found. Available: $avail" -ForegroundColor Red; exit 1
    }
    $cfg.voice.active_profile = $SetProfile
    Save-Config $cfg
    Write-Host "Voice profile: $SetProfile" -ForegroundColor Green; exit 0
}

if ($Mute) {
    $cfg = Get-Config; $cfg.audio.enabled = $false; Save-Config $cfg
    Write-Host "Audio muted." -ForegroundColor Yellow; exit 0
}
if ($Unmute) {
    $cfg = Get-Config; $cfg.audio.enabled = $true; Save-Config $cfg
    Write-Host "Audio unmuted." -ForegroundColor Green; exit 0
}

if ($Toggle) {
    $cfg = Get-Config
    switch ($Toggle.ToLower()) {
        "audio"         { $cfg.audio.enabled                  = -not $cfg.audio.enabled;                  $label = "Sound pack audio" }
        "repeat"        { $cfg.alerts.repeat_enabled             = -not $cfg.alerts.repeat_enabled;             $label = "Repeat alert" }
        "play-on-tool"  { $cfg.audio.play_on_tool             = -not $cfg.audio.play_on_tool;             $label = "Audio on tool events" }
        "terminal"      { $cfg.notify.terminal                = -not $cfg.notify.terminal;                $label = "Terminal banner" }
        "toast"         { $cfg.toast.enabled                  = -not $cfg.toast.enabled;                  $label = "Toast popups" }
        "tool-events"   { $cfg.toast.show_tool_events         = -not $cfg.toast.show_tool_events;         $label = "Toast on tool events" }
        "voice"         { $cfg.voice.enabled                  = -not $cfg.voice.enabled;                  $label = "Voice TTS" }
        "mobile"        { $cfg.mobile.enabled                 = -not $cfg.mobile.enabled;                 $label = "Mobile push" }
        "complete-push" { $cfg.mobile.push_on_complete        = -not $cfg.mobile.push_on_complete;        $label = "Push on complete" }
        "tool-details"  { $cfg.announcements.tool_details     = -not $cfg.announcements.tool_details;     $label = "Tool details" }
        default { Write-Host "Unknown feature: $Toggle. Run --help." -ForegroundColor Red; exit 1 }
    }
    Save-Config $cfg
    $newVal = switch ($Toggle.ToLower()) {
        "audio"         { $cfg.audio.enabled }
        "repeat"        { $cfg.alerts.repeat_enabled             = -not $cfg.alerts.repeat_enabled;             $label = "Repeat alert" }
        "repeat"        { $cfg.alerts.repeat_enabled }
        "play-on-tool"  { $cfg.audio.play_on_tool }
        "terminal"      { $cfg.notify.terminal }
        "toast"         { $cfg.toast.enabled }
        "tool-events"   { $cfg.toast.show_tool_events }
        "voice"         { $cfg.voice.enabled }
        "mobile"        { $cfg.mobile.enabled }
        "complete-push" { $cfg.mobile.push_on_complete }
        "tool-details"  { $cfg.announcements.tool_details }
    }
    $state = if ($newVal) { "ON" } else { "OFF" }
    $color = if ($newVal) { "Green" } else { "Yellow" }
    Write-Host "$label $state." -ForegroundColor $color; exit 0
}

if ($SetTopic) {
    $cfg = Get-Config
    $cfg.mobile.ntfy_topic = $SetTopic; $cfg.mobile.enabled = $true; Save-Config $cfg
    Write-Host "Mobile topic: $SetTopic" -ForegroundColor Green
    Write-Host "Subscribe at: $($cfg.mobile.ntfy_server)/$SetTopic" -ForegroundColor Cyan; exit 0
}

if ($Voices) {
    Add-Type -AssemblyName System.Speech
    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
    Write-Host ""; Write-Host "Installed TTS voices:" -ForegroundColor Cyan
    $synth.GetInstalledVoices() | ForEach-Object {
        Write-Host "  $($_.VoiceInfo.Name)  [$($_.VoiceInfo.Gender)]" -ForegroundColor White
    }
    $synth.Dispose()
    Write-Host "Add more: Settings > Time & language > Speech > Add voices" -ForegroundColor DarkGray; exit 0
}

if ($SetVoice) {
    $cfg = Get-Config
    if ($cfg.PSObject.Properties["profiles"] -and $cfg.voice.active_profile) {
        $pName = $cfg.voice.active_profile
        if ($cfg.profiles.PSObject.Properties[$pName]) {
            $cfg.profiles.$pName.name = $SetVoice; Save-Config $cfg
            Write-Host "Voice in '$pName' set to: $SetVoice" -ForegroundColor Green; exit 0
        }
    }
    $cfg.voice.name = $SetVoice; Save-Config $cfg
    Write-Host "Voice: $SetVoice" -ForegroundColor Green; exit 0
}


if ($SetInterval) {
    $n = [int]$SetInterval
    if ($n -lt 5 -or $n -gt 300) { Write-Host "Interval must be 5-300 seconds." -ForegroundColor Red; exit 1 }
    $cfg = Get-Config
    $cfg.alerts.repeat_interval_seconds = $n
    Save-Config $cfg
    Write-Host "Repeat interval set to: ${n}s" -ForegroundColor Green
    exit 0
}

if ($Test) {
    $cfg          = Get-Config
    $notifyScript = Join-Path $PSScriptRoot "engine\notify.ps1"
    $pack         = $cfg.audio.active_pack
    Write-Host ""
    Write-Host "Testing claude-herald..." -ForegroundColor Cyan
    Write-Host "  Audio pack: $pack  vol=$($cfg.audio.volume)" -ForegroundColor DarkGray
    Write-Host "  (sounds play async - you will hear them shortly after each banner)" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "Event: done" -ForegroundColor DarkGray
    & $notifyScript -Event "done"       -Message "Process concluded. Standing by for your directive."
    Start-Sleep -Milliseconds 1800

    Write-Host "Event: question" -ForegroundColor DarkGray
    & $notifyScript -Event "question"   -Message "There is something I need clarification on."
    Start-Sleep -Milliseconds 1800

    Write-Host "Event: permission" -ForegroundColor DarkGray
    & $notifyScript -Event "permission" -Message "Authorization required. Please review and respond."
    Start-Sleep -Milliseconds 1800

    Write-Host "Event: tool (Write)" -ForegroundColor DarkGray
    & $notifyScript -Event "tool"       -Message "File updated." -Detail "Skills.md"
    Start-Sleep -Milliseconds 1000

    Write-Host "Test complete." -ForegroundColor Green
    Write-Host ""
    exit 0
}