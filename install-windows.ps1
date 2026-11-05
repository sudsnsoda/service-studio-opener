<#
.SYNOPSIS
  Installs and configures the Service Studio "studio-opener" MCP server on Windows,
  so Claude Code can open OutSystems 11 modules by itself.

.DESCRIPTION
  What it does (each step is safe to re-run):
    1. Finds Python 3.10+ (installs 3.12 with winget if missing)
    2. Creates the project folder and a virtual environment, installs "mcp<2" and pywinauto
    3. Writes server.py (the opener) into the project folder
    4. Installs Claude Code with Anthropic's official PowerShell installer, and fixes PATH
    5. Registers two MCP servers with Claude Code (user scope):
         studio-opener  -> the opener from this script
         servicestudio  -> http://127.0.0.1:<port>/mcp (Service Studio's built-in MCP server)
    6. Installs the OutSystems "servicestudio-mcp-oml" skill from GitHub (ZIP, no git needed)
    7. Writes CLAUDE.md rules into the project folder
    8. Installs any *.skill files found next to this script into ~\.claude\skills

  What it cannot do (you do these by hand, the script prints them at the end):
    - Start the MCP server in Service Studio (Edit > MCP Server > Start MCP Server)
    - Log in to Claude Code the first time
    - Approve Service Studio's "allow this agent?" prompt

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -SkipClaudeInstall -SkipSkill
#>
[CmdletBinding()]
param(
    [string]$ProjectDir = (Join-Path $HOME 'os_mcp_agent'),
    [int]$McpPort = 41820,
    [switch]$SkipClaudeInstall,
    [switch]$SkipSkill,
    [switch]$SkipRegister
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Say($m)  { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "    OK   $m" -ForegroundColor Green }
function Warn($m) { Write-Host "    NOTE $m" -ForegroundColor Yellow }
function Fail($m) { Write-Host "    ERR  $m" -ForegroundColor Red; throw $m }

function Get-GoodPython {
    $candidates = New-Object System.Collections.Generic.List[string]
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try {
            $p = "$(& py -3 -c 'import sys; print(sys.executable)' 2>$null)".Trim()
            if ($p) { $candidates.Add($p) }
        } catch { }
    }
    $pc = Get-Command python -ErrorAction SilentlyContinue
    if ($pc -and $pc.Source -notlike '*WindowsApps*') { $candidates.Add($pc.Source) }
    Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | ForEach-Object { $candidates.Add($_.FullName) }
    foreach ($c in $candidates) {
        try {
            $v = "$(& $c -c 'import sys; print(int(sys.version_info >= (3,10)))' 2>$null)".Trim()
            if ($v -eq '1') { return $c }
        } catch { }
    }
    return $null
}

function Test-InUserPath($dir) {
    $p = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $p) { return $false }
    return (($p -split ';') | Where-Object { $_.TrimEnd('\') -ieq $dir.TrimEnd('\') }).Count -gt 0
}

try {
    Write-Host "Service Studio opener installer (Windows)" -ForegroundColor White
    Write-Host "Project folder: $ProjectDir"

    # ---- 1. Python -------------------------------------------------------
    Say "Checking Python 3.10 or newer"
    $python = Get-GoodPython
    if (-not $python) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Fail "Python 3.10+ not found and winget is not available. Install Python 3.12 from python.org, then run this script again."
        }
        Warn "Python 3.10+ not found. Installing Python 3.12 with winget."
        & winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
        $python = Get-GoodPython
        if (-not $python) {
            Fail "Python was installed but this window cannot see it yet. Close PowerShell, open a new one, and run this script again."
        }
    }
    Ok "Using $python"

    # ---- 2. Folder, venv, packages ---------------------------------------
    Say "Creating the project folder and virtual environment"
    New-Item -ItemType Directory -Force $ProjectDir | Out-Null
    $venv   = Join-Path $ProjectDir 'studio-opener'
    $venvPy = Join-Path $venv 'Scripts\python.exe'
    if (Test-Path $venvPy) {
        $v = "$(& $venvPy -c 'import sys; print(int(sys.version_info >= (3,10)))' 2>$null)".Trim()
        if ($v -ne '1') {
            Warn "Existing virtual environment uses an old Python. Recreating it."
            Remove-Item $venv -Recurse -Force
        }
    }
    if (-not (Test-Path $venvPy)) {
        & $python -m venv $venv
        if ($LASTEXITCODE -ne 0) { Fail "Could not create the virtual environment." }
    }
    Ok "Virtual environment: $venv"

    Say "Installing packages (mcp<2 and pywinauto)"
    & $venvPy -m pip install --quiet --disable-pip-version-check "mcp<2" pywinauto
    if ($LASTEXITCODE -ne 0) { Fail "pip install failed." }
    & $venvPy -c "import pywinauto; from mcp.server.fastmcp import FastMCP"
    if ($LASTEXITCODE -ne 0) { Fail "Packages installed but cannot be imported." }
    Ok "Packages installed (mcp is pinned below 2.x because 2.x renamed FastMCP)"

    # ---- 3. server.py ----------------------------------------------------
    Say "Writing server.py"
    $serverPy = Join-Path $ProjectDir 'server.py'
    $serverCode = @'
import re, sys, time, threading
from pywinauto import Desktop
from pywinauto.keyboard import send_keys
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("studio-opener")
lock = threading.Lock()


def main_window():
    for w in Desktop(backend="uia").windows(title="Service Studio"):
        for c in w.children():
            if c.element_info.automation_id == "tabs":
                return w, c
    return None, None


def open_tabs(tabs):
    out = {}
    for t in tabs.children():
        if t.element_info.class_name != "TabItem":
            continue
        for tx in t.descendants(control_type="Text"):
            s = re.sub(r"^\*\s*", "", tx.window_text()).split(" (")[0].strip()
            if s:
                out[s] = t
                break
    return out


def poll(fn, timeout, interval=0.5):
    end = time.time() + timeout
    while time.time() < end:
        r = fn()
        if r:
            return r
        time.sleep(interval)


@mcp.tool()
def list_open_modules() -> str:
    """List modules currently open as tabs in Service Studio."""
    w, tabs = main_window()
    if not w:
        return "ERROR: Service Studio main window not found"
    return "\n".join(sorted(open_tabs(tabs))) or "(none)"


@mcp.tool()
def activate_module(name: str) -> str:
    """Bring an already-open module's tab to the front."""
    with lock:
        w, tabs = main_window()
        if not w:
            return "ERROR: Service Studio main window not found"
        t = open_tabs(tabs).get(name)
        if not t:
            return f"ERROR: {name} is not open"
        t.click_input()
        return f"{name} activated"


@mcp.tool()
def ensure_module_open(name: str, timeout: int = 90) -> str:
    """Open a module in Service Studio via Ctrl+O if it is not already open."""
    if not re.fullmatch(r"\w+", name):
        return "ERROR: module name has special characters; refusing"
    with lock:
        w, tabs = main_window()
        if not w:
            return "ERROR: Service Studio main window not found"
        if name in open_tabs(tabs):
            return f"{name} already open"

        w.set_focus()
        send_keys("^o")

        def find_dialog():
            for c in w.children():
                if c.element_info.name == "Open from Environment":
                    return c

        dlg = poll(find_dialog, 10)
        if not dlg:
            return "ERROR: Open dialog did not appear"

        def button(label):
            for b in dlg.descendants(control_type="Button"):
                if b.window_text() == label:
                    return b

        def cancel(msg):
            b = button("Cancel")
            if b:
                b.invoke()
            return msg

        edit = next((e for e in dlg.descendants(control_type="Edit")
                     if e.window_text().startswith("Search for Module")), None)
        if not edit:
            return cancel("ERROR: search box not found; dialog cancelled")
        edit.set_focus()
        send_keys("^a{BACKSPACE}")
        send_keys(name)

        def find_row():
            for row in dlg.descendants(control_type="DataItem"):
                texts = [t.window_text() for t in row.descendants(control_type="Text")]
                if texts and texts[0] == name:
                    return row

        row = poll(find_row, 15)
        if not row:
            return cancel(f"ERROR: no exact match for {name}; dialog cancelled")

        row.click_input()
        time.sleep(0.5)
        button("Open").invoke()

        def is_open():
            _, t = main_window()
            return t is not None and name in open_tabs(t)

        ok = poll(is_open, timeout, 1)
        return f"{name} open" if ok else f"TIMEOUT opening {name}"


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--test":
        print(ensure_module_open(sys.argv[2]))
    elif len(sys.argv) > 2 and sys.argv[1] == "--activate":
        print(activate_module(sys.argv[2]))
    elif len(sys.argv) > 1 and sys.argv[1] == "--list":
        print(list_open_modules())
    else:
        mcp.run()
'@
    $serverCode = $serverCode.Replace("`r`n", "`n").TrimEnd() + "`n"
    $existing = $null
    if (Test-Path $serverPy) { $existing = [System.IO.File]::ReadAllText($serverPy).Replace("`r`n", "`n") }
    if ($existing -ne $serverCode) {
        if ($existing) {
            Copy-Item $serverPy "$serverPy.bak" -Force
            Warn "Existing server.py differed; saved a copy as server.py.bak"
        }
        [System.IO.File]::WriteAllText($serverPy, $serverCode, $utf8NoBom)
    }
    Ok "$serverPy"

    # ---- 4. Claude Code --------------------------------------------------
    Say "Checking Claude Code"
    $localBin = Join-Path $HOME '.local\bin'
    if (-not (Get-Command claude -ErrorAction SilentlyContinue) -and -not (Test-Path (Join-Path $localBin 'claude.exe'))) {
        if ($SkipClaudeInstall) {
            Warn "Claude Code is not installed and -SkipClaudeInstall was given."
        } else {
            Warn "Installing Claude Code with Anthropic's official installer (irm https://claude.ai/install.ps1 | iex)"
            Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression
        }
    }
    if ((Test-Path (Join-Path $localBin 'claude.exe')) -and -not (Test-InUserPath $localBin)) {
        $up = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($up) { $up = $up.TrimEnd(';') + ';' + $localBin } else { $up = $localBin }
        [Environment]::SetEnvironmentVariable('Path', $up, 'User')
        Ok "Added $localBin to your user PATH (new PowerShell windows will see it)"
    }
    if (($env:Path -split ';') -notcontains $localBin -and (Test-Path $localBin)) {
        $env:Path = "$env:Path;$localBin"
    }
    $claude = Get-Command claude -ErrorAction SilentlyContinue
    if ($claude) { Ok "claude found: $($claude.Source)" } else { Warn "claude is not available in this window yet." }

    # ---- 5. Register MCP servers ----------------------------------------
    if ($SkipRegister -or -not $claude) {
        Warn "Skipping MCP registration. Run these yourself once claude works:"
        Write-Host "      claude mcp add --scope user studio-opener -- `"$venvPy`" `"$serverPy`""
        Write-Host "      claude mcp add --transport http --scope user servicestudio http://127.0.0.1:$McpPort/mcp"
    } else {
        Say "Registering MCP servers with Claude Code"
        Push-Location $ProjectDir
        try {
            $listed = (& claude mcp list 2>&1 | Out-String)
            if ($listed -match 'studio-opener') {
                Ok "studio-opener already registered (to change it: claude mcp remove studio-opener)"
            } else {
                & claude mcp add --scope user studio-opener -- $venvPy $serverPy
                if ($LASTEXITCODE -ne 0) { Fail "Could not register studio-opener." }
                Ok "studio-opener registered"
            }
            if ($listed -match 'servicestudio') {
                Ok "servicestudio already registered"
            } else {
                & claude mcp add --transport http --scope user servicestudio "http://127.0.0.1:$McpPort/mcp"
                if ($LASTEXITCODE -ne 0) { Fail "Could not register servicestudio." }
                Ok "servicestudio registered (http://127.0.0.1:$McpPort/mcp)"
            }
        } finally { Pop-Location }
    }

    # ---- 6. OutSystems skill ---------------------------------------------
    $skillsDir = Join-Path $HOME '.claude\skills'
    if ($SkipSkill) {
        Warn "Skipping the OutSystems skill (-SkipSkill)."
    } else {
        Say "Installing the OutSystems servicestudio-mcp-oml skill (GitHub ZIP, no git needed)"
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ('os11mcp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $tmp | Out-Null
        try {
            $zip = Join-Path $tmp 'repo.zip'
            Invoke-WebRequest 'https://github.com/OutSystems/outsystems11-mcp/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
            Expand-Archive $zip -DestinationPath $tmp -Force
            $src = Join-Path $tmp 'outsystems11-mcp-main\servicestudio-mcp-oml'
            if (-not (Test-Path (Join-Path $src 'SKILL.md'))) { Fail "The downloaded repository has no servicestudio-mcp-oml\SKILL.md; the layout may have changed." }
            New-Item -ItemType Directory -Force $skillsDir | Out-Null
            Copy-Item $src $skillsDir -Recurse -Force
            Ok "Skill copied to $skillsDir\servicestudio-mcp-oml"
        } finally {
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # ---- 7. CLAUDE.md ----------------------------------------------------
    Say "Writing CLAUDE.md rules"
    $claudeMd = Join-Path $ProjectDir 'CLAUDE.md'
    $marker = '<!-- studio-opener rules -->'
    $rules = @"
$marker
Before any OutSystems MCP call on module X:
1. Call ensure_module_open(X).
2. Call activate_module(X) so X is the active tab, then continue.
3. If any tool returns ERROR or TIMEOUT, stop and tell me. Never retry in a loop.
4. If ensure_module_open reports it opened a different module, stop. Do not continue.
Use exact module names (letters, digits, underscore), never display names.
Never close modules or click save/discard/publish dialogs.
"@
    $current = ''
    if (Test-Path $claudeMd) { $current = [System.IO.File]::ReadAllText($claudeMd) }
    if ($current -notlike "*$marker*") {
        $sep = ''
        if ($current -and -not $current.EndsWith("`n")) { $sep = "`n" }
        [System.IO.File]::AppendAllText($claudeMd, $sep + $rules.Replace("`r`n", "`n") + "`n", $utf8NoBom)
        Ok "Rules added to $claudeMd"
    } else {
        Ok "Rules already present in $claudeMd"
    }

    # ---- 8. Extra skills next to this script ----------------------------
    $extra = @()
    if ($PSScriptRoot) { $extra = @(Get-ChildItem -Path $PSScriptRoot -Filter '*.skill' -ErrorAction SilentlyContinue) }
    if ($extra.Count -gt 0) {
        Say "Installing .skill files found next to this script"
        New-Item -ItemType Directory -Force $skillsDir | Out-Null
        foreach ($f in $extra) {
            $z = Join-Path ([IO.Path]::GetTempPath()) ($f.BaseName + '.zip')
            Copy-Item $f.FullName $z -Force
            try { Expand-Archive $z -DestinationPath $skillsDir -Force } finally { Remove-Item $z -Force -ErrorAction SilentlyContinue }
            Ok "$($f.Name) installed to $skillsDir"
        }
        Warn "If a skill with the same name is already installed through a plugin, remove one of the two copies."
    }

    # ---- Done ------------------------------------------------------------
    Write-Host ""
    Write-Host "Installation finished." -ForegroundColor Green
    Write-Host @"

WHAT TO DO NEXT (by hand)
  1. In Service Studio: Edit > MCP Server > Start MCP Server (keep port $McpPort).
     Do this again after every Service Studio restart.
  2. Open a NEW PowerShell window, then:
       cd $ProjectDir
       claude mcp list          (both servers should show Connected)
       claude                   (log in when the browser opens)
  3. Approve the prompt that Service Studio shows when Claude Code connects.
  4. Test the opener alone, with a module that is NOT open yet (hands off the keyboard and mouse):
       & "$venvPy" "$serverPy" --test YourModuleName
     Other checks:  --list    and    --activate YourModuleName
  5. Test the whole chain in Claude Code:
       Summarize module YourModuleName

NOTES
  - Run PowerShell and Service Studio at the same privilege level (both normal, or both admin).
  - The opener uses the real mouse and keyboard while it runs. Do not type elsewhere meanwhile.
  - Keep reads first: the Service Studio MCP write tools are Beta and run C# with Studio's privileges.
  - If getDataModel fails with "Could not find file ...-in.oml", check %TEMP%\ServiceStudio.MCPServer,
    antivirus, and pending dialogs, then restart the MCP server (Edit > MCP Server).
  - To undo: claude mcp remove studio-opener ; claude mcp remove servicestudio ;
    delete $ProjectDir and $skillsDir\servicestudio-mcp-oml
"@
}
catch {
    Write-Host ""
    Write-Host "Installation stopped: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
