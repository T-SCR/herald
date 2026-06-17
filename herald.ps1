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
    [switch]$Leaving,
    [Alias('home')][switch]$ImHome,
    [switch]$SetupTelegram,
    [switch]$Bridge,
    [switch]$StopBridge,
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
           -or $Voices -or $Mute -or $Unmute -or $Leaving -or $ImHome -or $SetupTelegram `
           -or $Bridge -or $StopBridge

if ($Leaving) {
    $cfg = Get-Config
    $cfg.away_mode = $true
    Save-Config $cfg
    $name = if ($cfg.tone.mode -eq "sir") { "sir" } else { $cfg.tone.name }
    Write-Host "Away mode ON - all events will push to your phone." -ForegroundColor Yellow
    Write-Host "Local sounds and banners suspended." -ForegroundColor DarkGray

    # Notify phone via Telegram
    if ($cfg.mobile.enabled -and $cfg.mobile.telegram_bot_token -and $cfg.mobile.telegram_chat_id) {
        $pushScript = Join-Path $PSScriptRoot "engine\push.ps1"
        & $pushScript -Title "Claude Herald - Away mode on" `
            -Body "You have left. I will push everything to your phone — task completions, questions, and anything that needs your attention." `
            -Priority "default"
        Write-Host "Phone notified via Telegram." -ForegroundColor Green
    } elseif ($cfg.mobile.enabled) {
        Write-Host "Telegram not configured. Run: .\herald.ps1 --setup-telegram" -ForegroundColor Yellow
    }

    # Start reply-listener now so it's ready before the first question arrives
    if ($cfg.mobile.enabled -and $cfg.mobile.telegram_bot_token) {
        $pidFile        = Join-Path $PSScriptRoot ".reply-listener-pid"
        $listenerScript = Join-Path $PSScriptRoot "engine\reply-listener.ps1"
        $isRunning      = $false
        if (Test-Path $pidFile) {
            $savedPid = (Get-Content $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
            if ($savedPid -and (Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue)) {
                $isRunning = $true
            }
        }
        if (-not $isRunning) {
            Start-Process powershell -WindowStyle Hidden -ArgumentList @(
                "-NoProfile", "-NonInteractive", "-File", "`"$listenerScript`""
            )
            Write-Host "Reply listener started - phone replies will paste into Claude." -ForegroundColor DarkGray
        } else {
            Write-Host "Reply listener already running." -ForegroundColor DarkGray
        }
    }
    exit 0
}

if ($ImHome) {
    $cfg = Get-Config
    $cfg.away_mode = $false
    Save-Config $cfg
    $name = if ($cfg.tone.mode -eq "sir") { "sir" } else { $cfg.tone.name }
    Write-Host "Welcome back! Away mode OFF - resuming normal notifications." -ForegroundColor Green

    # Play "Welcome home, sir."
    if ($cfg.audio.enabled) {
        $packDir     = Join-Path $PSScriptRoot "sounds\$($cfg.audio.active_pack)"
        $welcomeFile = Join-Path $packDir "sounds\session_start_1.mp3"
        $playScript  = Join-Path $PSScriptRoot "engine\play.ps1"
        if (Test-Path $welcomeFile) {
            & $playScript -Path $welcomeFile -Volume ([double]$cfg.audio.volume)
        }
    }

    # Push confirmation via Telegram
    if ($cfg.mobile.enabled -and $cfg.mobile.telegram_bot_token -and $cfg.mobile.telegram_chat_id) {
        $pushScript = Join-Path $PSScriptRoot "engine\push.ps1"
        & $pushScript -Title "Claude Herald - Welcome back, $name" `
            -Body "You are back. Switching to home mode - only important alerts will reach your phone now." `
            -Priority "low"
    }
    exit 0
}

if ($SetupTelegram) {
    Write-Host ""
    Write-Host "Telegram Bot Setup" -ForegroundColor Cyan
    Write-Host "------------------" -ForegroundColor DarkGray
    Write-Host "1. Open Telegram and message @BotFather"
    Write-Host "2. Send: /newbot  (follow prompts to name your bot)"
    Write-Host "3. BotFather will give you a token like: 1234567890:ABCdef..."
    Write-Host ""
    $token = Read-Host "Paste your bot token"
    if ([string]::IsNullOrWhiteSpace($token)) { Write-Host "Cancelled." -ForegroundColor Red; exit 1 }

    $cfg = Get-Config
    $cfg.mobile.telegram_bot_token = $token.Trim()
    Save-Config $cfg

    Write-Host ""
    Write-Host "Token saved. Now send ANY message to your bot in Telegram." -ForegroundColor Yellow
    Write-Host "Waiting up to 60 seconds..." -ForegroundColor DarkGray

    $baseUrl = "https://api.telegram.org/bot$($token.Trim())"
    $found   = $false
    for ($i = 0; $i -lt 12; $i++) {
        Start-Sleep -Seconds 5
        try {
            $resp = Invoke-RestMethod -Uri "$baseUrl/getUpdates?timeout=0" -ErrorAction Stop
            foreach ($upd in $resp.result) {
                $cid = $null
                if ($upd.message)            { $cid = [string]$upd.message.chat.id }
                elseif ($upd.callback_query) { $cid = [string]$upd.callback_query.message.chat.id }
                if ($cid) {
                    $cfg = Get-Config
                    $cfg.mobile.telegram_chat_id = $cid
                    $cfg.mobile.enabled = $true
                    Save-Config $cfg
                    Write-Host "Chat ID detected: $cid" -ForegroundColor Green

                    # Send confirmation
                    $body = @{ chat_id = $cid; text = "Herald connected! I will push Claude events here when you are away." } | ConvertTo-Json -Compress
                    Invoke-RestMethod -Uri "$baseUrl/sendMessage" -Method Post `
                        -Body $body -ContentType "application/json" -ErrorAction SilentlyContinue | Out-Null

                    Write-Host ""
                    Write-Host "Setup complete." -ForegroundColor Green
                    Write-Host "Run: .\herald.ps1 --leaving   to activate away mode" -ForegroundColor DarkGray
                    $found = $true
                    break
                }
            }
        } catch {
            Write-Host "Error contacting Telegram: $_" -ForegroundColor Red
            break
        }
        if ($found) { break }
    }
    if (-not $found) {
        Write-Host "No message detected. Make sure you sent a message to the bot and try again." -ForegroundColor Red
    }
    exit 0
}

if ($StopBridge) {
    $pidFile = Join-Path $PSScriptRoot ".bridge-pid"
    if (Test-Path $pidFile) {
        $savedPid = (Get-Content $pidFile -Raw).Trim()
        $proc = Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id ([int]$savedPid) -Force
            Write-Host "Bridge stopped (PID $savedPid)." -ForegroundColor Yellow
        } else {
            Write-Host "Bridge process not found (stale PID)." -ForegroundColor DarkGray
        }
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "Bridge is not running." -ForegroundColor DarkGray
    }
    exit 0
}

if ($Bridge) {
    # Stop reply-listener — bridge handles all Telegram polling
    $rlPid = Join-Path $PSScriptRoot ".reply-listener-pid"
    if (Test-Path $rlPid) {
        $savedPid = (Get-Content $rlPid -Raw -ErrorAction SilentlyContinue).Trim()
        if ($savedPid -and (Get-Process -Id ([int]$savedPid) -ErrorAction SilentlyContinue)) {
            Stop-Process -Id ([int]$savedPid) -Force -ErrorAction SilentlyContinue
            Write-Host "Reply listener stopped (bridge takes over)." -ForegroundColor DarkGray
        }
        Remove-Item $rlPid -Force -ErrorAction SilentlyContinue
    }

    # Check Python
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) {
        Write-Host "Python not found. Install Python 3.8+ and run: pip install anthropic requests" -ForegroundColor Red
        exit 1
    }

    # Check ANTHROPIC_API_KEY
    if (-not $env:ANTHROPIC_API_KEY) {
        Write-Host "ANTHROPIC_API_KEY not set." -ForegroundColor Red
        Write-Host 'Set it with: $env:ANTHROPIC_API_KEY = "sk-ant-..."' -ForegroundColor Yellow
        exit 1
    }

    $bridgeScript = Join-Path $PSScriptRoot "engine\telegram-claude-bridge.py"
    $pyExe        = "C:\Python313\python.exe"
    if (-not (Test-Path $pyExe)) { $pyExe = "python" }
    Write-Host "Starting Herald Claude Bridge..." -ForegroundColor Cyan
    Start-Process $pyExe -ArgumentList "`"$bridgeScript`"" -WindowStyle Hidden
    Start-Sleep -Seconds 2

    $pidFile = Join-Path $PSScriptRoot ".bridge-pid"
    if (Test-Path $pidFile) {
        $pid = (Get-Content $pidFile -Raw).Trim()
        Write-Host "Bridge running (PID $pid). Check Telegram." -ForegroundColor Green
        Write-Host "Stop with: .\herald.ps1 --stop-bridge" -ForegroundColor DarkGray
    } else {
        Write-Host "Bridge may have failed to start. Check herald.log" -ForegroundColor Red
    }
    exit 0
}

if ($Help -or (-not $anyFlag)) {
    Write-Host ""
    Write-Host "claude-herald" -ForegroundColor Cyan
    Write-Host "Notification bridge for Claude Code" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\herald.ps1 --status                   All current settings"
    Write-Host "  .\herald.ps1 --test                     Fire all 4 event types now"
    Write-Host "  .\herald.ps1 --leaving                  Away mode ON  (push everything to Telegram)"
    Write-Host "  .\herald.ps1 --home                     Away mode OFF (welcome back + resume local)"
    Write-Host "  .\herald.ps1 --setup-telegram           Connect Telegram bot (guided)"
    Write-Host "  .\herald.ps1 --bridge                   Start Claude agent in Telegram"
    Write-Host "  .\herald.ps1 --stop-bridge              Stop the Telegram Claude agent"
    Write-Host "  .\herald.ps1 --packs                    List installed sound packs"
    Write-Host "  .\herald.ps1 --set-pack <name>          Switch active sound pack"
    Write-Host "  .\herald.ps1 --set-volume 0.0-1.0       Set audio volume"
    Write-Host "  .\herald.ps1 --toggle <feature>         Toggle on/off"
    Write-Host "  .\herald.ps1 --mute / --unmute          Quick audio mute"
    Write-Host "  .\herald.ps1 --voices                   List installed TTS voices"
    Write-Host "  .\herald.ps1 --set-profile <name>       Switch TTS voice profile"
    Write-Host ""
    Write-Host "Toggleable features:" -ForegroundColor Yellow
    Write-Host "  audio         Sound pack playback              [default: ON]"
    Write-Host "  terminal      Styled banner in Claude terminal [default: ON]"
    Write-Host "  toast         Windows toast popups             [default: ON]"
    Write-Host "  voice         TTS voice (off by default)       [default: OFF]"
    Write-Host "  mobile        Telegram push (away mode)        [default: OFF]"
    Write-Host "  play-on-tool  Play sound on tool events        [default: OFF]"
    Write-Host "  tool-events   Toast on tool events"
    Write-Host "  complete-push Push to Telegram on task-done"
    Write-Host ""
    exit 0
}

if ($Status) {
    $cfg = Get-Config
    Write-Host ""
    Write-Host "claude-herald status" -ForegroundColor Cyan
    Write-Host "--------------------" -ForegroundColor DarkGray
    $awayLabel = if ($cfg.away_mode) { "[AWAY] All events -> phone" } else { "[HOME] Local + attention push" }
    $awayColor = if ($cfg.away_mode) { "Yellow" } else { "Green" }
    Write-Host "  Mode: $awayLabel" -ForegroundColor $awayColor
    Write-Host "    --leaving / --home to switch" -ForegroundColor DarkGray
    Write-Host ""
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
    $tgStatus = if ($cfg.mobile.telegram_chat_id) { "connected (chat $($cfg.mobile.telegram_chat_id))" } else { "(not set — run --setup-telegram)" }
    Write-Host "    Telegram: $tgStatus" -ForegroundColor DarkGray
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
        "tone"          { $cfg.tone.mode = if ($cfg.tone.mode -eq "sir") { "friendly" } else { "sir" }; $label = "Tone mode (now: $($cfg.tone.mode))" }
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
        "tone"          { $cfg.tone.mode = if ($cfg.tone.mode -eq "sir") { "friendly" } else { "sir" }; $label = "Tone mode (now: $($cfg.tone.mode))" }
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