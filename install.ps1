<#
.SYNOPSIS
    claude-herald installer.
    Registers Stop and PostToolUse hooks in your global Claude Code settings.
    Run once. Re-run to update hook paths if you move the install directory.
#>

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

Write-Host ""
Write-Host "claude-herald installer" -ForegroundColor Cyan
Write-Host "-----------------------" -ForegroundColor DarkGray

# 1. Locate Claude Code global settings
$claudeSettings = "$env:USERPROFILE\.claude\settings.json"

if (-not (Test-Path $claudeSettings)) {
    Write-Host "[!] Claude Code settings not found at: $claudeSettings" -ForegroundColor Yellow
    Write-Host "    Make sure Claude Code is installed first." -ForegroundColor Yellow
    Write-Host "    Creating minimal settings file..." -ForegroundColor DarkGray
    New-Item -ItemType Directory -Force -Path (Split-Path $claudeSettings) | Out-Null
    '{}' | Set-Content $claudeSettings -Encoding UTF8
}

# 2. Read existing settings
$settingsRaw = Get-Content $claudeSettings -Raw
$settings    = $settingsRaw | ConvertFrom-Json

# 3. Build hook commands
$pwsh       = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) { $pwsh = (Get-Command powershell).Source }

$stopCmd    = "$pwsh -NoProfile -NonInteractive -File `"$root\hooks\on-stop.ps1`""
$toolCmd    = "$pwsh -NoProfile -NonInteractive -File `"$root\hooks\on-tool-use.ps1`""

# 4. Inject hooks (preserve any existing hooks)
if (-not $settings.PSObject.Properties["hooks"]) {
    $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value ([PSCustomObject]@{})
}

# Stop hook
$stopHook = [PSCustomObject]@{
    hooks = @(
        [PSCustomObject]@{ type = "command"; command = $stopCmd }
    )
}
if (-not $settings.hooks.PSObject.Properties["Stop"]) {
    $settings.hooks | Add-Member -MemberType NoteProperty -Name "Stop" -Value @($stopHook)
} else {
    # Remove any existing claude-herald Stop entry, re-add
    $existing = @($settings.hooks.Stop | Where-Object {
        -not ($_.hooks | Where-Object { $_.command -like "*claude-herald*" })
    })
    $settings.hooks.Stop = @($existing) + @($stopHook)
}

# PostToolUse hook
$toolHook = [PSCustomObject]@{
    hooks = @(
        [PSCustomObject]@{ type = "command"; command = $toolCmd }
    )
}
if (-not $settings.hooks.PSObject.Properties["PostToolUse"]) {
    $settings.hooks | Add-Member -MemberType NoteProperty -Name "PostToolUse" -Value @($toolHook)
} else {
    $existing = @($settings.hooks.PostToolUse | Where-Object {
        -not ($_.hooks | Where-Object { $_.command -like "*claude-herald*" })
    })
    $settings.hooks.PostToolUse = @($existing) + @($toolHook)
}

# 5. Save settings
$settings | ConvertTo-Json -Depth 20 | Set-Content $claudeSettings -Encoding UTF8
Write-Host "[OK] Hooks registered in: $claudeSettings" -ForegroundColor Green

# 6. Test TTS
Write-Host ""
Write-Host "Testing voice..." -ForegroundColor Cyan
try {
    & "$root\herald.ps1" --test
} catch {
    Write-Host "[!] Voice test failed: $_" -ForegroundColor Yellow
    Write-Host "    Run: .\herald.ps1 --voices  to see available voices." -ForegroundColor DarkGray
}

# 7. Print next steps
Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  .\herald.ps1 --status              See all settings"
Write-Host "  .\herald.ps1 --voices              List available TTS voices"
Write-Host "  .\herald.ps1 --set-topic <topic>   Enable mobile push (ntfy.sh)"
Write-Host "  .\herald.ps1 --toggle tool-events  Toggle per-tool toast popups"
Write-Host ""
Write-Host "Restart Claude Code for hooks to take effect." -ForegroundColor Cyan
Write-Host ""
