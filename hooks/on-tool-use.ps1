<#
.SYNOPSIS
    Claude Code PostToolUse hook handler.
    Fires after each tool call. Announces significant tool events.
    Deliberately quiet for high-frequency tools (Read, Grep, Glob).
#>

$root        = Split-Path $PSScriptRoot -Parent
$configPath  = Join-Path $root "config.json"
$linesPath   = Join-Path $root "voice\lines.json"
$speakScript = Join-Path $root "engine\speak.ps1"
$toastScript = Join-Path $root "engine\toast.ps1"

if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.enabled)              { exit 0 }
if (-not $config.hooks.on_tool_use)    { exit 0 }

$lines = Get-Content $linesPath -Raw | ConvertFrom-Json

# Read hook payload from stdin
$payload = $null
try {
    $raw = $input | Out-String
    if ($raw.Trim()) { $payload = $raw | ConvertFrom-Json }
} catch { exit 0 }

if (-not $payload) { exit 0 }

$toolName = $payload.tool_name

# Tools to stay silent on — too frequent, not interesting
$silentTools = @("Read", "Glob", "Grep", "mcp__qmd__query", "mcp__qmd__get",
                 "mcp__qmd__multi_get", "ToolSearch", "advisor")

if ($toolName -in $silentTools) { exit 0 }

# Build a context-aware message
$message   = $null
$toastBody = $null

switch -Regex ($toolName) {
    "^Write$" {
        $filePath  = $payload.tool_input.file_path
        $fileName  = if ($filePath) { Split-Path $filePath -Leaf } else { "file" }
        $pool      = $lines.tool.Write
        $base      = $pool[(Get-Random -Maximum $pool.Count)]
        $message   = if ($config.announcements.tool_details) { "$base — $fileName" } else { $base }
        $toastBody = "Written: $fileName"
    }
    "^Edit$" {
        $filePath  = $payload.tool_input.file_path
        $fileName  = if ($filePath) { Split-Path $filePath -Leaf } else { "file" }
        $pool      = $lines.tool.Edit
        $base      = $pool[(Get-Random -Maximum $pool.Count)]
        $message   = if ($config.announcements.tool_details) { "$base — $fileName" } else { $base }
        $toastBody = "Edited: $fileName"
    }
    "^Bash$" {
        $cmd       = $payload.tool_input.command
        $preview   = if ($cmd -and $cmd.Length -gt 50) { $cmd.Substring(0, 47) + "..." } else { $cmd }
        $pool      = $lines.tool.Bash
        $base      = $pool[(Get-Random -Maximum $pool.Count)]
        $message   = if ($config.announcements.tool_details -and $preview) { "$base — $preview" } else { $base }
        $toastBody = "Command: $preview"
    }
    "^WebFetch$" {
        $pool      = $lines.tool.WebFetch
        $message   = $pool[(Get-Random -Maximum $pool.Count)]
        $toastBody = "Web content retrieved"
    }
    "^WebSearch$" {
        $pool      = $lines.tool.WebSearch
        $message   = $pool[(Get-Random -Maximum $pool.Count)]
        $toastBody = "Search complete"
    }
    "^Agent$" {
        $pool      = $lines.tool.Agent
        $message   = $pool[(Get-Random -Maximum $pool.Count)]
        $toastBody = "Agent dispatched"
    }
    "^TodoWrite$" {
        $pool      = $lines.tool.TodoWrite
        $message   = $pool[(Get-Random -Maximum $pool.Count)]
        $toastBody = "Task list updated"
    }
    default {
        # Unknown tool — announce briefly without details
        $message   = "Operation complete."
        $toastBody = "Tool: $toolName"
    }
}

if ($message) {
    & $speakScript -Message $message -Priority "low"
}

if ($toastBody -and $config.toast.show_tool_events) {
    & $toastScript -Title "Claude — $toolName" -Body $toastBody
}
