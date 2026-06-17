<#
.SYNOPSIS
    Core TTS engine for claude-herald.
    Reads config and speaks a message with the configured voice profile.
.PARAMETER Message
    Text to speak.
.PARAMETER Priority
    low | normal | high — controls whether to interrupt or queue.
#>
param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet("low","normal","high")][string]$Priority = "normal"
)

$configPath = Join-Path $PSScriptRoot "..\config.json"
if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.voice.enabled) { exit 0 }

try {
    Add-Type -AssemblyName System.Speech

    $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer

    # Apply voice selection — fall back gracefully
    $targetVoice = $config.voice.name
    $installed = $synth.GetInstalledVoices() | ForEach-Object { $_.VoiceInfo.Name }
    if ($installed -contains $targetVoice) {
        $synth.SelectVoice($targetVoice)
    }

    $synth.Rate   = [int]$config.voice.rate      # -10 to 10
    $synth.Volume = [int]$config.voice.volume     # 0 to 100

    if ($Priority -eq "high") {
        $synth.SpeakAsync($Message) | Out-Null
    } else {
        $synth.Speak($Message)
    }

    $synth.Dispose()
} catch {
    # TTS failure is non-fatal — log silently
    $_ | Out-File (Join-Path $PSScriptRoot "..\herald.log") -Append
}
