# Service Studio Opener

Claude Code can open the OutSystems 11 module it needs in Service Studio by itself, so the Service Studio MCP always has the module it must read. The Service Studio MCP only sees modules that are open, and opening one by hand each time is the step this setup removes.

Two MCP servers work together, both registered in Claude Code:

| Server | What it is | Runs on |
| --- | --- | --- |
| `studio-opener` | A small Python server that opens modules by driving Service Studio's Open from Environment dialog (Windows UI Automation, macOS Accessibility) | Your machine, started by Claude Code |
| `servicestudio` | Service Studio's built-in MCP server, which reads the open modules | Inside Service Studio, at `http://127.0.0.1:41820/mcp` |

For each module, Claude Code calls `ensure_module_open`, then `activate_module`, then reads the module with the `servicestudio` tools. It stops and reports on any error instead of retrying.

```
Claude Code --(ensure_module_open, activate_module)--> studio-opener --(UI automation)--> Service Studio: Open from Environment dialog --> open module tab
Claude Code --(HTTP, read tools)--------------------------------------------------------> Service Studio built-in MCP server --> reads the open module
```

## Repository layout

| Path | What it is |
| --- | --- |
| `install-windows.ps1` | Windows installer (PowerShell) |
| `install-macos.sh` | macOS installer (bash) |
| `src/server_win.py`, `src/server_mac.py` | The opener servers. The installers embed these; edit here, then regenerate the installers |
| `skills/service-studio-auto-module-open-os11` | Service Studio Auto-Module Open for OS11: opens O11 modules through `ensure_module_open` before reading them |

## Requirements

| Item | Windows | macOS |
| --- | --- | --- |
| Service Studio | 11.55.91 or later | The macOS build of Service Studio 11, with Edit > MCP Server present |
| Python | 3.10 or newer; `winget` installs 3.12 if missing | 3.10 or newer; the Python shipped with macOS is too old. Homebrew installs 3.12 if missing |
| Claude Code | Installed by the script (native, in PowerShell, not WSL) | Installed by the script |
| Permissions | PowerShell and Service Studio at the same level (both normal or both admin) | Accessibility access for your terminal app |
| Python packages | `mcp<2`, `pywinauto` | `mcp<2`, PyObjC (ApplicationServices, Cocoa, Quartz) |
| Keyboard layout | Any | US layout assumed for Cmd+O, Cmd+V and Cmd+A |

Run everything on the Windows or macOS side. The opener drives a Windows or macOS app, so it cannot run inside WSL or a Linux container.

## Quick install

Run the installer for your system, then do the manual steps it prints at the end. Both scripts are safe to run again.

Windows (PowerShell, not WSL):

```powershell
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1
```

macOS (Terminal):

```bash
bash install-macos.sh
```

Options: `-SkipClaudeInstall`, `-SkipSkill`, `-SkipRegister` on Windows; `--skip-claude-install`, `--skip-skill`, `--skip-register`, `--project-dir`, `--port` on macOS. Any `.skill` file placed next to the script is installed too, into `~/.claude/skills`.

The scripts download from GitHub and run Anthropic's official Claude Code installer, so read them before running.

After the script finishes:

1. Start the MCP server in Service Studio (see below).
2. Open a new terminal window and run `claude mcp list`. Both servers should show Connected.
3. Run the three tests in "Verify the installation".

## What the installer does

The project folder is `C:\Users\<you>\os_mcp_agent` on Windows and `~/os_mcp_agent` on macOS.

1. **Check Python 3.10 or newer.** Windows: `py --version` (install with `winget install Python.Python.3.12`, then open a new PowerShell). macOS: `python3 --version` (install with `brew install python@3.12`).
2. **Create the virtual environment** in the project folder: `py -m venv studio-opener` (Windows) or `python3 -m venv venv` (macOS).
3. **Install the packages** with the environment's own pip:
   - Windows: `.\studio-opener\Scripts\pip.exe install "mcp<2" pywinauto`
   - macOS: `./venv/bin/pip install "mcp<2" pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa pyobjc-framework-Quartz`
4. **Write the opener server**: `server.py` (Windows) or `server_mac.py` (macOS) into the project folder.
5. **Install Claude Code.** Windows: `irm https://claude.ai/install.ps1 | iex`. macOS: `curl -fsSL https://claude.ai/install.sh | bash`. Make sure `~/.local/bin` is on your PATH and open a new terminal.
6. **Grant Accessibility access (macOS only).** System Settings > Privacy & Security > Accessibility: turn on your terminal app, quit it with Cmd+Q and reopen it.
7. **Register both MCP servers** from the project folder:
   - `claude mcp add --scope user studio-opener -- <python in the venv> <server file>`
   - `claude mcp add --transport http --scope user servicestudio http://127.0.0.1:41820/mcp`
8. **Install the OutSystems skill** `servicestudio-mcp-oml`: download the `OutSystems/outsystems11-mcp` repository ZIP (branch main) and copy the `servicestudio-mcp-oml` folder into `~/.claude/skills`. The repository's own installer needs git, which is why the script copies the folder directly.
9. **Write `CLAUDE.md`** into the project folder with the rules below.

## Start the Service Studio MCP server

The built-in MCP server does not start on its own, so start it once per Service Studio session. This step cannot be automated, because the menu is drawn inside a web view.

1. Open any module in Service Studio.
2. Go to **Edit > MCP Server**.
3. Keep port `41820` (it moves up to 20 ports if busy; use the port the dialog shows when it differs) and click **Start MCP Server**.
4. In Claude Code, run `claude mcp list` and check that `servicestudio` shows Connected.
5. The first time Claude Code connects, Service Studio shows an "allow this agent?" prompt. Approve it yourself.

Repeat steps 2 to 5 after every Service Studio restart. If Claude Code loses the connection, run `/mcp reconnect servicestudio` and approve the prompt again. Never automate the approval click, because it is the security gate for what the agent can do.

## Configuration

| What | Where | Notes |
| --- | --- | --- |
| Opener server | `os_mcp_agent\server.py` (Windows), `os_mcp_agent/server_mac.py` (macOS) | Tools: `list_open_modules`, `ensure_module_open`, `activate_module` |
| Virtual environment | `os_mcp_agent\studio-opener` (Windows), `os_mcp_agent/venv` (macOS) | Use this Python for the server and for the tests |
| `studio-opener` registration | Claude Code, user scope | Works from any folder. Change it with `claude mcp remove studio-opener`, then add it again |
| `servicestudio` registration | Claude Code, user scope, HTTP | `http://127.0.0.1:41820/mcp`; change the port if the dialog shows another |
| Rules for Claude | `os_mcp_agent\CLAUDE.md` | Applies only when Claude Code starts in that folder. Copy it to `~/.claude/CLAUDE.md` to apply everywhere |
| OutSystems skill | `~/.claude/skills/servicestudio-mcp-oml` | Reload by starting a new Claude Code session |
| Timing (macOS) | `TYPE_DELAY` (1.0 s) and `FILTER_DELAY` (2.5 s) at the top of `server_mac.py` | Raise them if names are pasted too early or Enter fires before the list filters |

The `CLAUDE.md` rules the installer writes:

```
Before any OutSystems MCP call on module X:
1. Call ensure_module_open(X).
2. Call activate_module(X) so X is the active tab, then continue.
3. If any tool returns ERROR or TIMEOUT, stop and tell me. Never retry in a loop.
4. If ensure_module_open reports it opened a different module, stop. Do not continue.
Use exact module names (letters, digits, underscore), never display names.
Never close modules or click save/discard/publish dialogs.
```

Rules are instructions, not enforcement. If Claude calls an OutSystems tool without opening the module first, report it and consider a hook that blocks the call.

## Verify the installation

Run three tests in this order, with the Service Studio MCP server started. Keep your hands off the keyboard and mouse during tests 2 and 3, because the opener uses the real ones.

1. **Both servers connect.** In a new terminal, run `claude mcp list`. `studio-opener` and `servicestudio` should both show Connected. Connected only proves the processes started, not that the tools work.
2. **The opener works alone.** Pick a module that is not open yet and run the server file with the environment's Python:
   - Windows: `.\studio-opener\Scripts\python.exe server.py --test YourModuleName`
   - macOS: `./venv/bin/python server_mac.py --test YourModuleName`
   - Expected: `YourModuleName open`. Also try `--list` (shows open tabs) and `--activate YourModuleName`.
3. **The whole chain works.** In `claude`, started from the project folder, ask: `Summarize module YourModuleName`. Approve the Service Studio prompt. Check that the summary describes the module you named, and also test a module that sits in a background tab.

If test 3 describes the active module instead of the one you named, the Service Studio MCP only follows the active tab. The `activate_module` rule already covers that case.

## Using it

Name the module in your request, and Claude Code opens it before reading. Start with read-only tasks.

| You want | Prompt example |
| --- | --- |
| Read one module | `Summarize module Worker_CS` |
| Read several modules | `List the server actions of Operations_BL and Job_CS` (they open one at a time) |
| Migrate to ODC | Use the `service-studio-auto-module-open-os11` skill; it opens each O11 module it needs with `ensure_module_open` |

The skills live in `skills/`. Package a folder as a `.skill` file (a ZIP with the folder at its top level) to upload it in claude.ai or to place next to the installer. Each open takes over the mouse and keyboard for a few seconds, so do not type in other windows while Claude Code works on a new module.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `py` or `claude` "is not recognized" right after installing | The open window still has the old PATH | Close the terminal and open a new one. For `claude`, also add `C:\Users\<you>\.local\bin` to the user PATH |
| `pip install` says "externally-managed-environment" | You are in WSL or using the system Python | Do not use `--break-system-packages`. Use the Windows or macOS side and the project's virtual environment |
| `No module named 'mcp.server.fastmcp'` | `mcp` 2.x installed; it renamed `FastMCP` | `pip install "mcp<2"` in the environment |
| `No matching distribution found for mcp<2` (macOS) | The environment uses Python older than 3.10 | Install Python 3.12, delete `os_mcp_agent/venv` only, recreate it, reinstall |
| `UnicodeEncodeError ... charmap` in a dump script | PowerShell cannot print a character in a window title | `$env:PYTHONUTF8 = "1"` before running Python |
| `Trusted for accessibility: False` (macOS) | The terminal app has no Accessibility access | System Settings > Privacy & Security > Accessibility (not the Accessibility page with VoiceOver), enable the terminal, quit it with Cmd+Q, reopen |
| macOS dialog opens but the name is not typed | Web view ignores single key events | Fixed by the clipboard paste in the current `server_mac.py` |
| `ERROR: Service Studio ... not found` or `not running` | Opener cannot see Service Studio, or it runs at another privilege level | Start Service Studio; run both at the same level |
| `ERROR: Open dialog did not appear` | Another dialog or approval prompt is in the way | Close it and retry once |
| `ERROR: no exact match` or `no match for X` | Name is wrong, or the list was slow | Use the exact module name; on macOS raise `FILTER_DELAY` |
| `ERROR: opened X instead of Y` | A different row ranked first | Close tab X yourself, and use the exact name |
| `TIMEOUT opening X` | Tab never appeared within 90 s | Check for a save or login dialog |
| `ConnectionRefused` on `servicestudio` | MCP server not started | Edit > MCP Server > Start MCP Server |
| `-32000 Could not find file ...-in.oml` | The MCP's temporary copy of the module is missing | Check the temp folder `ServiceStudio.MCPServer`, antivirus and pending dialogs, then restart the MCP server. The cause is not yet confirmed |
| Test 2 works but Claude Code's call fails | Claude Code starts the server in another security context | Check the Accessibility grant (macOS) or elevation (Windows) of the app that launches Claude Code |

A failure that appears once and then clears usually means timing or focus: a click elsewhere during the call, or a prompt that appeared late.

## Limits and security

**Limits**

- Starting the Service Studio MCP server and approving each connection stay manual.
- The opener takes over the real mouse and keyboard for a few seconds per module, so it needs the machine unattended or a dedicated session.
- On macOS the dialog's contents are not readable, so the opener cannot check the highlighted row before pressing Enter. It verifies the new tab afterwards, and a wrong module can open before it is detected.
- Key codes assume a US keyboard layout on macOS.
- Whether the Service Studio MCP sees modules in background tabs was not confirmed. `activate_module` is always called to be safe.
- Window layout or Service Studio updates can break the automation.

**Security**

- Accessibility (macOS) and UI Automation (Windows) let a process read and control other apps. Grant Accessibility only to the terminal you use, and remove it when you stop using the setup.
- The approval prompt in Service Studio is the control that limits what the agent can do. Approve only agents you trust, and never automate the click.
- Once approved, the Service Studio MCP write tools (Beta) compile and run code with Service Studio's privileges. Use read tools first, and never let a documentation or migration run call the write tools.
- Do not close tabs or press save, discard or publish through automation. Tabs marked `*` may hold unsaved work.
- The installers download from GitHub's `main` branch and run Anthropic's installer script. Read them before running, and pin versions if your policy requires it.

## Update and uninstall

To update, run the installer again: it keeps your settings, backs up a changed server file as `.bak`, and replaces the OutSystems skill with the latest copy from GitHub.

To uninstall:

1. Remove the registrations: `claude mcp remove studio-opener` and `claude mcp remove servicestudio`.
2. Delete the project folder (`os_mcp_agent`), which holds the virtual environment, the server file and `CLAUDE.md`.
3. Delete `~/.claude/skills/servicestudio-mcp-oml`, and any `.skill` folders you installed there.
4. macOS: turn off Accessibility access for your terminal app if you no longer need it.
5. Optional: stop the MCP server in Service Studio (Edit > MCP Server). Claude Code can stay installed.
