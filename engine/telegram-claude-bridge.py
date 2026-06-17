#!/usr/bin/env python3
"""
Herald Telegram-Claude Bridge
Full two-way Claude agent accessible from Telegram.
Claude can run PowerShell commands on the laptop, read/write files,
and respond with real results — all from your phone.

Usage: python engine/telegram-claude-bridge.py
Stop:  herald.ps1 --stop-bridge
"""

import anthropic
import json
import os
import subprocess
import sys
import time
import requests
from pathlib import Path

ROOT        = Path(__file__).parent.parent
CONFIG_PATH = ROOT / "config.json"
PID_PATH    = ROOT / ".bridge-pid"
LOG_PATH    = ROOT / "herald.log"


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)

config  = load_config()
TOKEN   = config["mobile"]["telegram_bot_token"]
CHAT_ID = str(config["mobile"]["telegram_chat_id"])
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

if not TOKEN or not CHAT_ID:
    print("ERROR: Telegram not configured. Run: herald.ps1 --setup-telegram")
    sys.exit(1)

if not API_KEY:
    print("ERROR: ANTHROPIC_API_KEY environment variable not set.")
    print("Set it with: $env:ANTHROPIC_API_KEY = 'your-key-here'")
    sys.exit(1)

client   = anthropic.Anthropic(api_key=API_KEY)
BASE_URL = f"https://api.telegram.org/bot{TOKEN}"

# In-memory conversation history (reset with /clear)
history = []

SYSTEM_PROMPT = """You are Claude, running as a personal assistant via Telegram with full access to the user's Windows laptop.

You can run PowerShell commands, read/write files, and do real work on the machine.
The user is Sharat — a Monash student, startup founder (FoundAI/Sprint 2026), targeting AI Engineer internships.
Active projects: Claude Herald (this tool), Monash Startup Sprint 2026, Portfolio Website.

Guidelines:
- Be concise — this is a Telegram chat, not a document editor
- For multi-step work: send one brief "Working on X..." then do it, then report results
- Summarise what you did in 2-3 sentences after completing work
- Use code blocks for command output (wrap in ``` ```)
- If asked to do something risky or destructive, confirm first
- Working directory is the user's home or wherever they specify
"""

TOOLS = [
    {
        "name": "bash",
        "description": "Run a PowerShell command on the user's Windows laptop. Use for any real work: running scripts, git, npm, reading output, checking status, etc.",
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {
                    "type": "string",
                    "description": "PowerShell command to run"
                },
                "working_dir": {
                    "type": "string",
                    "description": "Optional working directory (absolute path). Defaults to user home."
                }
            },
            "required": ["command"]
        }
    },
    {
        "name": "read_file",
        "description": "Read a file from the laptop. Returns content as text.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Absolute file path"
                }
            },
            "required": ["path"]
        }
    },
    {
        "name": "write_file",
        "description": "Write or overwrite a file on the laptop.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path":    {"type": "string", "description": "Absolute file path"},
                "content": {"type": "string", "description": "Content to write"}
            },
            "required": ["path", "content"]
        }
    },
    {
        "name": "list_dir",
        "description": "List files in a directory on the laptop.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Absolute directory path"}
            },
            "required": ["path"]
        }
    }
]


# ---------------------------------------------------------------------------
# Tool execution
# ---------------------------------------------------------------------------

def run_tool(name: str, inputs: dict) -> str:
    if name == "bash":
        try:
            cwd = inputs.get("working_dir") or str(Path.home())
            result = subprocess.run(
                ["powershell", "-NoProfile", "-NonInteractive", "-Command", inputs["command"]],
                capture_output=True, text=True, timeout=60, cwd=cwd
            )
            out = (result.stdout + result.stderr).strip()
            if not out:
                return "(no output)"
            return out[:3000] + ("\n... (truncated)" if len(out) > 3000 else "")
        except subprocess.TimeoutExpired:
            return "Timed out after 60 seconds."
        except Exception as e:
            return f"Error: {e}"

    elif name == "read_file":
        try:
            content = Path(inputs["path"]).read_text(encoding="utf-8", errors="replace")
            return content[:3000] + ("\n... (truncated)" if len(content) > 3000 else "")
        except Exception as e:
            return f"Error reading file: {e}"

    elif name == "write_file":
        try:
            p = Path(inputs["path"])
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(inputs["content"], encoding="utf-8")
            return f"Written: {inputs['path']} ({len(inputs['content'])} chars)"
        except Exception as e:
            return f"Error writing file: {e}"

    elif name == "list_dir":
        try:
            items = list(Path(inputs["path"]).iterdir())
            lines = [f"{'[D]' if i.is_dir() else '[F]'} {i.name}" for i in sorted(items)]
            return "\n".join(lines[:100]) or "(empty)"
        except Exception as e:
            return f"Error listing dir: {e}"

    return f"Unknown tool: {name}"


# ---------------------------------------------------------------------------
# Telegram helpers
# ---------------------------------------------------------------------------

def tg(endpoint: str, **kwargs) -> dict:
    try:
        resp = requests.post(f"{BASE_URL}/{endpoint}", json=kwargs, timeout=10)
        return resp.json()
    except Exception as e:
        log(f"Telegram error ({endpoint}): {e}")
        return {}

def send_message(text: str) -> dict:
    """Send (or chunk) a message to the user."""
    if len(text) <= 4000:
        return tg("sendMessage", chat_id=CHAT_ID, text=text)
    # Chunk long messages
    result = {}
    for i in range(0, len(text), 4000):
        result = tg("sendMessage", chat_id=CHAT_ID, text=text[i:i+4000])
    return result

def edit_message(message_id: int, text: str):
    """Edit the placeholder message in-place — used for live progress."""
    if len(text) > 4000:
        text = text[:3997] + "..."
    tg("editMessageText", chat_id=CHAT_ID, message_id=message_id, text=text)

def send_typing():
    tg("sendChatAction", chat_id=CHAT_ID, action="typing")

def answer_callback(callback_id: str):
    tg("answerCallbackQuery", callback_query_id=callback_id)

def log(msg: str):
    with open(LOG_PATH, "a") as f:
        f.write(f"[{time.strftime('%H:%M:%S')}] bridge: {msg}\n")


# ---------------------------------------------------------------------------
# Core agent loop
# ---------------------------------------------------------------------------

def process(user_text: str):
    global history
    history.append({"role": "user", "content": user_text})

    # Send a live placeholder message — we'll edit it as work progresses
    placeholder = send_message("...")
    msg_id = placeholder.get("result", {}).get("message_id")

    try:
        step = 0
        while True:
            send_typing()
            response = client.messages.create(
                model="claude-sonnet-4-6",
                max_tokens=8096,
                system=SYSTEM_PROMPT,
                tools=TOOLS,
                messages=history
            )
            history.append({"role": "assistant", "content": response.content})

            if response.stop_reason == "end_turn":
                parts = [b.text for b in response.content if hasattr(b, "text")]
                final = "\n".join(parts).strip() or "(done)"
                if msg_id:
                    edit_message(msg_id, final)
                    msg_id = None  # sent
                else:
                    send_message(final)
                log(f"done after {step} tool steps")
                break

            elif response.stop_reason == "tool_use":
                tool_results = []
                for block in response.content:
                    if block.type != "tool_use":
                        continue
                    step += 1
                    # Show user what's running
                    preview = json.dumps(block.input).replace('"', "")[:120]
                    status  = f"Step {step}: {block.name}\n{preview}"
                    if msg_id:
                        edit_message(msg_id, status)

                    output = run_tool(block.name, block.input)
                    log(f"tool {block.name} -> {output[:80]}")
                    tool_results.append({
                        "type":        "tool_result",
                        "tool_use_id": block.id,
                        "content":     output
                    })
                    send_typing()

                history.append({"role": "user", "content": tool_results})

            else:
                # Unexpected stop reason
                if msg_id:
                    edit_message(msg_id, f"Stopped: {response.stop_reason}")
                break

    except Exception as e:
        err = f"Error: {e}"
        log(err)
        if msg_id:
            edit_message(msg_id, err)
        else:
            send_message(err)


# ---------------------------------------------------------------------------
# Update polling
# ---------------------------------------------------------------------------

def get_updates(offset: int) -> list:
    try:
        resp = requests.get(f"{BASE_URL}/getUpdates", params={
            "offset":          offset,
            "timeout":         10,
            "allowed_updates": ["message", "callback_query"]
        }, timeout=15)
        return resp.json().get("result", [])
    except Exception:
        return []


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    PID_PATH.write_text(str(os.getpid()))
    print(f"Herald Claude Bridge running  (PID {os.getpid()})")
    print(f"Listening on Telegram chat {CHAT_ID}")
    print("Stop with: herald.ps1 --stop-bridge")

    send_message(
        "Herald Bridge connected.\n\n"
        "Chat with me here — I can run commands and do real work on your laptop. "
        "Just tell me what you need.\n\n"
        "/clear — reset conversation\n"
        "/status — bridge info"
    )

    offset = 0
    while True:
        try:
            updates = get_updates(offset)
            for update in updates:
                offset = update["update_id"] + 1

                text = None
                if "message" in update:
                    msg = update["message"]
                    if str(msg["chat"]["id"]) == CHAT_ID and "text" in msg:
                        text = msg["text"]
                elif "callback_query" in update:
                    cq = update["callback_query"]
                    if str(cq["message"]["chat"]["id"]) == CHAT_ID:
                        text = cq["data"]
                        answer_callback(cq["id"])

                if not text:
                    continue

                log(f"received: {text[:80]}")

                if text == "/clear":
                    history.clear()
                    send_message("Conversation cleared.")
                elif text == "/status":
                    send_message(
                        f"Bridge running.\n"
                        f"Messages in history: {len(history)}\n"
                        f"Model: claude-sonnet-4-6"
                    )
                else:
                    process(text)

        except KeyboardInterrupt:
            print("Shutting down.")
            PID_PATH.unlink(missing_ok=True)
            break
        except Exception as e:
            log(f"main loop error: {e}")
            time.sleep(5)


if __name__ == "__main__":
    main()
