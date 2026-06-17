<#
.SYNOPSIS
    Windows toast notification engine for claude-herald.
    Uses BurntToast if available, falls back to native WinRT.
.PARAMETER Title
    Notification title.
.PARAMETER Body
    Notification body text.
.PARAMETER Icon
    Optional icon path.
#>
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$Body
)

$configPath = Join-Path $PSScriptRoot "..\config.json"
if (-not (Test-Path $configPath)) { exit 0 }

$config = Get-Content $configPath -Raw | ConvertFrom-Json
if (-not $config.toast.enabled) { exit 0 }

# Try BurntToast first (richest experience)
if (Get-Module -ListAvailable -Name BurntToast) {
    Import-Module BurntToast -ErrorAction SilentlyContinue
    New-BurntToastNotification -Text $Title, $Body -AppLogo "$PSScriptRoot\..\assets\icon.png" -ErrorAction SilentlyContinue
    exit 0
}

# Fall back to native Windows.UI.Notifications via WinRT
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

    $template = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>$Title</text>
      <text>$Body</text>
    </binding>
  </visual>
</toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($template)
    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Claude Herald")
    $notifier.Show($toast)
} catch {
    $_ | Out-File (Join-Path $PSScriptRoot "..\herald.log") -Append
}
