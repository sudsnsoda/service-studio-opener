#!/usr/bin/env bash
#
# Installs and configures the Service Studio "studio-opener" MCP server on macOS,
# so Claude Code can open OutSystems 11 modules by itself.
#
# What it does (each step is safe to re-run):
#   1. Finds Python 3.10+ (installs 3.12 with Homebrew if it is available and Python is missing)
#   2. Creates the project folder and a virtual environment, installs "mcp<2" and the PyObjC packages
#   3. Writes server_mac.py (the opener) into the project folder
#   4. Installs Claude Code with Anthropic's official installer and fixes PATH
#   5. Checks the macOS Accessibility permission (the opener needs it)
#   6. Registers two MCP servers with Claude Code (user scope):
#        studio-opener  -> the opener from this script
#        servicestudio  -> http://127.0.0.1:<port>/mcp (Service Studio's built-in MCP server)
#   7. Installs the OutSystems "servicestudio-mcp-oml" skill from GitHub (ZIP, no git needed)
#   8. Writes CLAUDE.md rules into the project folder
#   9. Installs any *.skill files found next to this script into ~/.claude/skills
#
# What it cannot do (you do these by hand, the script prints them at the end):
#   - Grant Accessibility access to your terminal app (System Settings)
#   - Start the MCP server in Service Studio (Edit > MCP Server > Start MCP Server)
#   - Log in to Claude Code the first time
#   - Approve Service Studio's "allow this agent?" prompt
#
# Usage:
#   bash install-macos.sh
#   bash install-macos.sh --skip-claude-install --skip-skill
#   bash install-macos.sh --project-dir "$HOME/work/os_mcp_agent" --port 41820

set -euo pipefail

PROJECT_DIR="$HOME/os_mcp_agent"
MCP_PORT="41820"
SKIP_CLAUDE=0
SKIP_SKILL=0
SKIP_REGISTER=0

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)         PROJECT_DIR="${2:?--project-dir needs a value}"; shift 2 ;;
    --port)                MCP_PORT="${2:?--port needs a value}"; shift 2 ;;
    --skip-claude-install) SKIP_CLAUDE=1; shift ;;
    --skip-skill)          SKIP_SKILL=1; shift ;;
    --skip-register)       SKIP_REGISTER=1; shift ;;
    -h|--help)             sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (try --help)"; exit 2 ;;
  esac
done

if [ -t 1 ]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_OFF=$'\033[0m'
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_OFF=""
fi
say()  { printf '\n%s==> %s%s\n' "$C_CYAN" "$1" "$C_OFF"; }
ok()   { printf '    %sOK%s   %s\n' "$C_GREEN" "$C_OFF" "$1"; }
warn() { printf '    %sNOTE%s %s\n' "$C_YELLOW" "$C_OFF" "$1"; }
die()  { printf '    %sERR%s  %s\n' "$C_RED" "$C_OFF" "$1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
  die "This installer is for macOS. On Windows use install-windows.ps1."
fi

echo "Service Studio opener installer (macOS)"
echo "Project folder: $PROJECT_DIR"

# ---- 1. Python ---------------------------------------------------------
find_python() {
  local c p
  for c in python3.13 python3.12 python3.11 python3.10 \
           /opt/homebrew/bin/python3.12 /usr/local/bin/python3.12 python3; do
    p="$(command -v "$c" 2>/dev/null || true)"
    [ -n "$p" ] || continue
    if "$p" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
      echo "$p"; return 0
    fi
  done
  return 1
}

say "Checking Python 3.10 or newer"
if ! PYTHON="$(find_python)"; then
  if command -v brew >/dev/null 2>&1; then
    warn "Python 3.10+ not found. Installing Python 3.12 with Homebrew."
    brew install python@3.12
    PYTHON="$(find_python)" || die "Homebrew installed Python but it was not found. Open a new Terminal and run this script again."
  else
    die "Python 3.10+ not found and Homebrew is not installed. Install Python 3.12 from python.org (or Homebrew, then 'brew install python@3.12'), then run this script again. The Python that ships with macOS is too old for the mcp package."
  fi
fi
ok "Using $PYTHON ($("$PYTHON" --version 2>&1))"

# ---- 2. Folder, venv, packages ----------------------------------------
say "Creating the project folder and virtual environment"
mkdir -p "$PROJECT_DIR"
VENV="$PROJECT_DIR/venv"
VENV_PY="$VENV/bin/python"
if [ -x "$VENV_PY" ]; then
  if ! "$VENV_PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
    warn "Existing virtual environment uses an old Python. Recreating it."
    [ "$(basename "$VENV")" = "venv" ] || die "Refusing to delete $VENV"
    rm -rf "$VENV"
  fi
fi
[ -x "$VENV_PY" ] || "$PYTHON" -m venv "$VENV"
ok "Virtual environment: $VENV"

say "Installing packages (mcp<2 and PyObjC)"
"$VENV_PY" -m pip install --quiet --disable-pip-version-check \
  "mcp<2" pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa pyobjc-framework-Quartz
"$VENV_PY" -c "import mcp.server.fastmcp, ApplicationServices, AppKit, Quartz" \
  || die "Packages installed but cannot be imported."
ok "Packages installed (mcp is pinned below 2.x because 2.x renamed FastMCP)"

# ---- 3. server_mac.py ---------------------------------------------------
say "Writing server_mac.py"
SERVER_PY="$PROJECT_DIR/server_mac.py"
NEW_SERVER="$(mktemp)"
cat > "$NEW_SERVER" <<'PYEOF'
import re, sys, time, threading
from ApplicationServices import (AXUIElementCreateApplication, AXUIElementCopyAttributeValue,
    AXUIElementSetAttributeValue, AXUIElementPerformAction)
from AppKit import NSWorkspace, NSPasteboard, NSPasteboardTypeString
from Quartz import (CGEventCreateKeyboardEvent, CGEventPost, CGEventSetFlags,
    kCGHIDEventTap, kCGEventFlagMaskCommand)
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("studio-opener")
lock = threading.Lock()
DIALOG_TITLE = "Open from Environment"
TYPE_DELAY = 1.0      # wait after the dialog appears, before pasting
FILTER_DELAY = 2.5    # wait for the list to filter, before Enter


def attr(el, name):
    err, val = AXUIElementCopyAttributeValue(el, name, None)
    return val if err == 0 else None


def texts(el):
    return [str(v) for k in ("AXValue", "AXTitle", "AXDescription", "AXIdentifier")
            if (v := attr(el, k)) not in (None, "")]


def descendants(el, depth=0):
    if depth > 30:
        return
    for c in attr(el, "AXChildren") or []:
        yield c
        yield from descendants(c, depth + 1)


def studio():
    for a in NSWorkspace.sharedWorkspace().runningApplications():
        if a.localizedName() == "Service Studio":
            return a


def ax_app(a):
    app = AXUIElementCreateApplication(a.processIdentifier())
    AXUIElementSetAttributeValue(app, "AXManualAccessibility", True)
    return app


def open_tabs(app):
    out = {}
    for w in attr(app, "AXWindows") or []:
        for el in descendants(w):
            if attr(el, "AXRole") == "AXTabGroup" and "tabs" in texts(el):
                for rb in descendants(el):
                    if attr(rb, "AXRole") != "AXRadioButton":
                        continue
                    if not any("AggregatorView" in t for t in texts(rb)):
                        continue
                    for tx in descendants(rb):
                        if attr(tx, "AXRole") == "AXStaticText" and texts(tx):
                            s = re.sub(r"^\*\s*", "", texts(tx)[0]).split(" (")[0].strip()
                            out[s] = rb
                            break
    return out


def dialog_open(app):
    return any(attr(w, "AXTitle") == DIALOG_TITLE for w in attr(app, "AXWindows") or [])


def poll(fn, timeout, interval=0.5):
    end = time.time() + timeout
    while time.time() < end:
        r = fn()
        if r:
            return r
        time.sleep(interval)


def key(code, flags=0):
    for down in (True, False):
        e = CGEventCreateKeyboardEvent(None, code, down)
        if flags:
            CGEventSetFlags(e, flags)
        CGEventPost(kCGHIDEventTap, e)
        time.sleep(0.03)


def paste_text(s):
    pb = NSPasteboard.generalPasteboard()
    old = pb.stringForType_(NSPasteboardTypeString)
    pb.clearContents()
    pb.setString_forType_(s, NSPasteboardTypeString)
    time.sleep(0.2)
    key(9, kCGEventFlagMaskCommand)      # Cmd+V (key code 9 = V, US layout)
    time.sleep(0.5)
    if old is not None:
        pb.clearContents()
        pb.setString_forType_(old, NSPasteboardTypeString)


@mcp.tool()
def list_open_modules() -> str:
    """List modules currently open as tabs in Service Studio."""
    a = studio()
    if not a:
        return "ERROR: Service Studio is not running"
    return "\n".join(sorted(open_tabs(ax_app(a)))) or "(none)"


@mcp.tool()
def activate_module(name: str) -> str:
    """Bring an already-open module's tab to the front."""
    with lock:
        a = studio()
        if not a:
            return "ERROR: Service Studio is not running"
        rb = open_tabs(ax_app(a)).get(name)
        if not rb:
            return f"ERROR: {name} is not open"
        a.activateWithOptions_(2)
        ok = AXUIElementPerformAction(rb, "AXPress") == 0
        return f"{name} activated" if ok else f"ERROR: could not press the {name} tab"


@mcp.tool()
def ensure_module_open(name: str, timeout: int = 90) -> str:
    """Open a module in Service Studio (Cmd+O) if it is not already open."""
    if not re.fullmatch(r"\w+", name):
        return "ERROR: module name has special characters; refusing"
    with lock:
        a = studio()
        if not a:
            return "ERROR: Service Studio is not running"
        app = ax_app(a)
        before = set(open_tabs(app))
        if name in before:
            return f"{name} already open"
        a.activateWithOptions_(2)
        time.sleep(1.0)
        key(31, kCGEventFlagMaskCommand)                    # Cmd+O (key code 31 = O, US layout)
        if not poll(lambda: dialog_open(app), 10):
            return "ERROR: Open dialog did not appear"
        for w in attr(app, "AXWindows") or []:
            if attr(w, "AXTitle") == DIALOG_TITLE:
                AXUIElementPerformAction(w, "AXRaise")
        time.sleep(TYPE_DELAY)
        key(0, kCGEventFlagMaskCommand)                     # Cmd+A
        key(51)                                             # Delete
        paste_text(name)
        time.sleep(FILTER_DELAY)
        key(36)                                             # Enter
        if not poll(lambda: not dialog_open(app), 5):
            key(53)                                         # Escape
            return f"ERROR: no match for {name}; dialog cancelled"
        end = time.time() + timeout
        while time.time() < end:
            now = set(open_tabs(app))
            if name in now:
                return f"{name} open"
            new = now - before
            if new:
                return (f"ERROR: opened {', '.join(sorted(new))} instead of {name}; "
                        f"left open, close it manually")
            time.sleep(1)
        return f"TIMEOUT opening {name}"


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--test":
        print(ensure_module_open(sys.argv[2]))
    elif len(sys.argv) > 2 and sys.argv[1] == "--activate":
        print(activate_module(sys.argv[2]))
    elif len(sys.argv) > 1 and sys.argv[1] == "--list":
        print(list_open_modules())
    else:
        mcp.run()
PYEOF
if [ -f "$SERVER_PY" ] && ! cmp -s "$SERVER_PY" "$NEW_SERVER"; then
  cp "$SERVER_PY" "$SERVER_PY.bak"
  warn "Existing server_mac.py differed; saved a copy as server_mac.py.bak"
fi
cp "$NEW_SERVER" "$SERVER_PY"
rm -f "$NEW_SERVER"
ok "$SERVER_PY"

# ---- 4. Claude Code -----------------------------------------------------
say "Checking Claude Code"
LOCAL_BIN="$HOME/.local/bin"
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$LOCAL_BIN/claude" ]; then
  if [ "$SKIP_CLAUDE" -eq 1 ]; then
    warn "Claude Code is not installed and --skip-claude-install was given."
  else
    warn "Installing Claude Code with Anthropic's official installer (curl -fsSL https://claude.ai/install.sh | bash)"
    curl -fsSL https://claude.ai/install.sh | bash
  fi
fi
if [ -x "$LOCAL_BIN/claude" ]; then
  case ":$PATH:" in *":$LOCAL_BIN:"*) ;; *) export PATH="$LOCAL_BIN:$PATH" ;; esac
  case "${SHELL:-}" in
    */zsh)  RC="$HOME/.zshrc" ;;
    */bash) RC="$HOME/.bash_profile" ;;
    *)      RC="" ;;
  esac
  if [ -n "$RC" ] && ! grep -qs '\.local/bin' "$RC"; then
    printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$RC"
    ok "Added ~/.local/bin to PATH in $RC (new Terminal windows will see it)"
  fi
fi
if command -v claude >/dev/null 2>&1; then
  CLAUDE_OK=1; ok "claude found: $(command -v claude)"
else
  CLAUDE_OK=0; warn "claude is not available in this window yet."
fi

# ---- 5. Accessibility permission --------------------------------------
say "Checking the macOS Accessibility permission"
if "$VENV_PY" -c 'import sys; from ApplicationServices import AXIsProcessTrusted; sys.exit(0 if AXIsProcessTrusted() else 1)' 2>/dev/null; then
  ok "This terminal app already has Accessibility access"
else
  warn "This terminal app does NOT have Accessibility access yet. The opener cannot work without it."
  warn "Opening System Settings > Privacy & Security > Accessibility."
  echo "      Turn ON the app that runs your terminal (Terminal, iTerm, or VS Code),"
  echo "      then quit that app completely (Cmd+Q), reopen it, and run this script again to confirm."
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
fi

# ---- 6. Register MCP servers -----------------------------------------
if [ "$SKIP_REGISTER" -eq 1 ] || [ "$CLAUDE_OK" -eq 0 ]; then
  warn "Skipping MCP registration. Run these yourself once claude works:"
  echo "      claude mcp add --scope user studio-opener -- \"$VENV_PY\" \"$SERVER_PY\""
  echo "      claude mcp add --transport http --scope user servicestudio http://127.0.0.1:$MCP_PORT/mcp"
else
  say "Registering MCP servers with Claude Code"
  LISTED="$(cd "$PROJECT_DIR" && claude mcp list 2>&1 || true)"
  if printf '%s' "$LISTED" | grep -q 'studio-opener'; then
    ok "studio-opener already registered (to change it: claude mcp remove studio-opener)"
  else
    claude mcp add --scope user studio-opener -- "$VENV_PY" "$SERVER_PY" \
      || die "Could not register studio-opener."
    ok "studio-opener registered"
  fi
  if printf '%s' "$LISTED" | grep -q 'servicestudio'; then
    ok "servicestudio already registered"
  else
    claude mcp add --transport http --scope user servicestudio "http://127.0.0.1:$MCP_PORT/mcp" \
      || die "Could not register servicestudio."
    ok "servicestudio registered (http://127.0.0.1:$MCP_PORT/mcp)"
  fi
fi

# ---- 7. OutSystems skill ------------------------------------------------
SKILLS_DIR="$HOME/.claude/skills"
if [ "$SKIP_SKILL" -eq 1 ]; then
  warn "Skipping the OutSystems skill (--skip-skill)."
else
  say "Installing the OutSystems servicestudio-mcp-oml skill (GitHub ZIP, no git needed)"
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  curl -fsSL -o "$TMP/repo.zip" "https://github.com/OutSystems/outsystems11-mcp/archive/refs/heads/main.zip" \
    || die "Could not download the OutSystems repository."
  unzip -oq "$TMP/repo.zip" -d "$TMP"
  SRC="$TMP/outsystems11-mcp-main/servicestudio-mcp-oml"
  [ -f "$SRC/SKILL.md" ] || die "The downloaded repository has no servicestudio-mcp-oml/SKILL.md; the layout may have changed."
  mkdir -p "$SKILLS_DIR"
  rm -rf "$SKILLS_DIR/servicestudio-mcp-oml"
  cp -R "$SRC" "$SKILLS_DIR/"
  ok "Skill copied to $SKILLS_DIR/servicestudio-mcp-oml"
fi

# ---- 8. CLAUDE.md -------------------------------------------------------
say "Writing CLAUDE.md rules"
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
MARKER='<!-- studio-opener rules -->'
if [ -f "$CLAUDE_MD" ] && grep -qF "$MARKER" "$CLAUDE_MD"; then
  ok "Rules already present in $CLAUDE_MD"
else
  [ -s "$CLAUDE_MD" ] && printf '\n' >> "$CLAUDE_MD"
  cat >> "$CLAUDE_MD" <<'RULES'
<!-- studio-opener rules -->
Before any OutSystems MCP call on module X:
1. Call ensure_module_open(X).
2. Call activate_module(X) so X is the active tab, then continue.
3. If any tool returns ERROR or TIMEOUT, stop and tell me. Never retry in a loop.
4. If ensure_module_open reports it opened a different module, stop. Do not continue.
Use exact module names (letters, digits, underscore), never display names.
Never close modules or click save/discard/publish dialogs.
RULES
  ok "Rules added to $CLAUDE_MD"
fi

# ---- 9. Extra skills next to this script ---------------------------------
shopt -s nullglob
EXTRA=("$SCRIPT_DIR"/*.skill)
shopt -u nullglob
if [ "${#EXTRA[@]}" -gt 0 ]; then
  say "Installing .skill files found next to this script"
  mkdir -p "$SKILLS_DIR"
  for f in "${EXTRA[@]}"; do
    unzip -oq "$f" -d "$SKILLS_DIR"
    ok "$(basename "$f") installed to $SKILLS_DIR"
  done
  warn "If a skill with the same name is already installed through a plugin, remove one of the two copies."
fi

# ---- Done ---------------------------------------------------------------
cat <<DONE

Installation finished.

WHAT TO DO NEXT (by hand)
  1. System Settings > Privacy & Security > Accessibility: turn ON your terminal app,
     quit it completely (Cmd+Q) and reopen it. Re-run this script if unsure; step 5 reports the result.
  2. In Service Studio: Edit > MCP Server > Start MCP Server (keep port $MCP_PORT).
     Do this again after every Service Studio restart.
  3. In a NEW Terminal window:
       cd $PROJECT_DIR
       claude mcp list          (both servers should show Connected)
       claude                   (log in when the browser opens)
  4. Approve the prompt that Service Studio shows when Claude Code connects.
  5. Test the opener alone, with a module that is NOT open yet (hands off the keyboard and mouse):
       "$VENV_PY" "$SERVER_PY" --test YourModuleName
     Other checks:  --list    and    --activate YourModuleName
  6. Test the whole chain in Claude Code:
       Summarize module YourModuleName

NOTES
  - The opener uses the real mouse and keyboard while it runs. Do not type elsewhere meanwhile.
  - It pastes the module name through the clipboard (your text clipboard is restored afterwards).
  - Key codes assume a US keyboard layout (Cmd+O, Cmd+V, Cmd+A). Other layouts may need changes.
  - The Service Studio web content is not readable through Accessibility, so a wrong module can open
    before it is detected. The opener reports it and stops; close the extra tab yourself.
  - Keep reads first: the Service Studio MCP write tools are Beta and run C# with Studio's privileges.
  - If getDataModel fails with "Could not find file ...-in.oml", look in \$TMPDIR for a
    ServiceStudio.MCPServer folder, check antivirus and pending dialogs, then restart the MCP server.
  - To undo: claude mcp remove studio-opener ; claude mcp remove servicestudio ;
    delete $PROJECT_DIR and $SKILLS_DIR/servicestudio-mcp-oml
DONE
