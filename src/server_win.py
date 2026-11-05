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
