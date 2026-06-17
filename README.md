# claude-herald

> Voice + notification bridge for Claude Code. Stop babysitting your terminal.

When Claude finishes a task, needs your permission, or has a question — you hear it. No more tabbing back every 30 seconds to check if it's done.

Built for Windows. Uses native Windows TTS (no audio files, no dependencies), Windows toast notifications, and optional mobile push via [ntfy.sh](https://ntfy.sh).

---

## What you'll hear

| Event | Example |
|---|---|
| Task complete | *"Process concluded. Standing by for further instructions."* |
| Claude has a question | *"I have a question for you when you're ready."* |
| Needs your input | *"I require your guidance before proceeding."* |
| Permission required | *"Authorization required. Please review and respond."* |
| File written | *"File updated successfully — Skills.md"* |
| Command run | *"Shell operation complete — npm install"* |

Voice lines are randomized from a pool so it doesn't sound robotic and repetitive.

---

## Install

```powershell
git clone https://github.com/sharatchandrareddy2005/claude-herald.git
cd claude-herald
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Restart Claude Code after install.

---

## Quick controls

```powershell
.\herald.ps1 --status              # See all current settings
.\herald.ps1 --test                # Hear a test line right now
.\herald.ps1 --mute                # Silence voice (keeps toasts)
.\herald.ps1 --unmute              # Turn voice back on
.\herald.ps1 --toggle voice        # Toggle TTS on/off
.\herald.ps1 --toggle toast        # Toggle Windows toast popups
.\herald.ps1 --toggle mobile       # Toggle phone push
.\herald.ps1 --toggle tool-events  # Toggle per-tool toast popups
.\herald.ps1 --voices              # List installed TTS voices
.\herald.ps1 --set-voice "Microsoft Zira Desktop"
```

---

## Mobile push (ntfy.sh)

Get notified on your phone when Claude needs permission or input — even when you've stepped away.

1. Install the [ntfy app](https://ntfy.sh) on your phone (iOS/Android, free)
2. Pick a unique topic name (e.g. `sharat-claude-a7k2`)
3. Subscribe to it in the app
4. Run:

```powershell
.\herald.ps1 --set-topic sharat-claude-a7k2
```

Mobile push only fires when Claude actually needs you (permission, question, input) — not on every task completion, unless you want it:

```powershell
.\herald.ps1 --toggle complete-push
```

For private ntfy self-hosting, set `mobile.ntfy_server` in `config.json`.

---

## Configuration

All settings live in `config.json`. Edit directly or use `herald.ps1` toggles.

```json
{
  "enabled": true,
  "voice": {
    "enabled": true,
    "name": "Microsoft David Desktop",
    "rate": -2,
    "volume": 90
  },
  "toast": {
    "enabled": true,
    "show_tool_events": false
  },
  "mobile": {
    "enabled": false,
    "ntfy_server": "https://ntfy.sh",
    "ntfy_topic": "",
    "push_on_complete": false
  },
  "hooks": {
    "on_stop": true,
    "on_tool_use": true
  },
  "announcements": {
    "tool_details": true
  }
}
```

### Choosing a voice

Run `.\herald.ps1 --voices` to list what's installed. Some options on Windows:
- `Microsoft David Desktop` — male, neutral (default)
- `Microsoft Zira Desktop` — female, neutral
- `Microsoft Mark Desktop` — male, slightly different cadence

To install more voices: **Settings → Time & language → Speech → Add voices**.

### Adjusting voice character

In `config.json`:
- `rate`: `-10` (very slow) to `10` (very fast). `-2` gives a deliberate, measured delivery.
- `volume`: `0`–`100`

---

## How it works

Two Claude Code hooks are registered in `~/.claude/settings.json`:

| Hook | Fires when | What it does |
|---|---|---|
| `Stop` | Claude finishes a turn | Classifies stop reason, speaks + toasts |
| `PostToolUse` | After every tool call | Announces significant tools (Write/Edit/Bash) silently skips noisy ones (Read/Grep) |

The `Stop` hook inspects the last assistant message to classify the stop reason (task done, question, needs input, permission needed) and picks voice lines and push priority accordingly.

---

## Uninstall

Remove the two hook entries from `~/.claude/settings.json` (the ones pointing to `claude-herald`), then delete the project folder.

---

## Roadmap

- [ ] Ambient "processing" indicator sound
- [ ] Session wrap summary: *"Session complete — 3 files modified, 2 commands run"*
- [ ] Custom voice line editing via config
- [ ] macOS support (say command + osascript)
- [ ] Linux support (espeak / festival)
