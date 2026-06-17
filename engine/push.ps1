<#
.SYNOPSIS
    Mobile push notification via ntfy.sh for claude-herald.
    Sends a push to your phone when Claude needs attention.
.PARAMETER Title
    Notification title.
.PARAMETER Body
    Notification body.
.PARAMETER Priority
    min | low | default | high | urgent
#>
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Body,
    [ValidateSet("min","low","default","high","urgent")][string]$Priority = "default"
)

$configPath = Join-Path $PSScriptRoot "..\config.json"
if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.mobile.enabled) { exit 0 }

$topic  = $config.mobile.ntfy_topic
$server = $config.mobile.ntfy_server

if ([string]::IsNullOrWhiteSpace($topic)) {
    Write-Warning "claude-herald: mobile.ntfy_topic is not configured in config.json"
    exit 1
}

try {
    $url     = "$server/$topic"
    $headers = @{
        "Title"    = $Title
        "Priority" = $Priority
        "Tags"     = "robot,bell"
    }

    # Include optional auth token if set
    if (-not [string]::IsNullOrWhiteSpace($config.mobile.ntfy_token)) {
        $headers["Authorization"] = "Bearer $($config.mobile.ntfy_token)"
    }

    Invoke-RestMethod -Uri $url -Method Post -Body $Body -Headers $headers -ErrorAction Stop | Out-Null
} catch {
    $_ | Out-File (Join-Path $PSScriptRoot "..\herald.log") -Append
}
