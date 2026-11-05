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
