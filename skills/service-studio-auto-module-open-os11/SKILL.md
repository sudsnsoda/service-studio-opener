---
name: service-studio-auto-module-open-os11
description: Playbook for migrating an OutSystems 11 module to OutSystems Developer Cloud (ODC) — read the O11 source with the Service Studio MCP (opening the needed O11 modules automatically through the studio-opener tools), and build the ODC apps through OutSystems Mentor (ODC MCP). Use when the user asks to migrate, port, rebuild or convert an O11 module/screen/action/entity to ODC.
---

# Service Studio Auto-Module Open for OS11

Load the `outsystems:outsystems` skill before any ODC MCP call.

## Environment

- **ODC tenant and Development environment:** get them with `env_list` (the entry whose `purpose` is `Development`). Do not hardcode keys in this skill.
- **O11 source:** Service Studio MCP (`servicestudio`). Call `createSessionToken` once per session. The MCP only sees modules that are open in Service Studio, so open each module you need yourself with `ensure_module_open`, as described in "Opening O11 modules" below. Only if the `studio-opener` tools are missing from this session, fall back to asking the user to open each one.
- **ODC edits:** Mentor only (`mentor_start_session` → `mentor_prompt` → poll `mentor_get_run`). Publish only when the user says so.
- **Shared libraries:** find their keys with `context_search` or ask the user, and pass a library's key in `assetRefs`, or Mentor may not find it.

## Opening O11 modules (studio-opener)

The `servicestudio` MCP can only read modules that are open in Service Studio. The `studio-opener` MCP server (tools `list_open_modules`, `ensure_module_open`, `activate_module`) opens them through Service Studio's Open from Environment dialog, so the user does not have to. Use it every time a module is needed, including dependencies found while mapping (a `_CS` or `_BL` module called by the UI module).

Per module:

1. `ensure_module_open(<Module>)` with the exact module name (letters, digits, underscore). Accept `<Module> already open` or `<Module> open`; treat anything else as a failure.
2. `activate_module(<Module>)` so it is the active tab. The Service Studio MCP may act only on the active module, and the call is cheap.
3. `listApps` to confirm the module is loaded, then read it (`getScreen`, `getWebBlock`, `getServerAction`, `getClientAction`, `getDataModel`).

Rules for this loop:

- **Open one module at a time.** Each open takes over the mouse and keyboard for a few seconds, so tell the user not to type while it runs, and list the modules you plan to open before starting if there are more than a handful.
- **Stop and report the exact text, never retry in a loop,** on any of these:
  - `ERROR` or `TIMEOUT` from the opener (Service Studio not found, dialog did not appear, no match, timeout).
  - `ERROR: opened X instead of Y`. A different module opened; ask the user to close X, then stop.
  - MCP error `-32000 Could not find file ...-in.oml`. The MCP's temporary copy is missing. The user checks `%TEMP%\ServiceStudio.MCPServer`, antivirus and any open dialog, then restarts the MCP server (Edit > MCP Server).
  - Connection refused or a pending approval prompt. The user starts the MCP server in Service Studio and approves the prompt.
- **O11 is read-only.** Never call `applyModelApiCode`, `omlMerge`, `omlReset` or `omlPublish`, never close tabs, and never press save, discard or publish in a dialog. Tabs marked `*` may hold unsaved work.
- If the user says a module is already open, still call `ensure_module_open`; it returns immediately when the tab exists.
