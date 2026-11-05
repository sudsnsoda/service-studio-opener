---
name: o11-to-odc-migration
description: Playbook for migrating an OutSystems 11 module to OutSystems Developer Cloud (ODC) — read the O11 source with the Service Studio MCP (opening the needed O11 modules automatically through the studio-opener tools), and build the ODC apps through OutSystems Mentor (ODC MCP). Use when the user asks to migrate, port, rebuild or convert an O11 module/screen/action/entity to ODC.
---

# O11 → ODC migration

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

## Ground rules

1. **Mirror O11 1:1.** Same screens, blocks, widget tree, style classes, aggregate joins and filters, actions, variables and logic. No redesigns or skipped widgets. If something can't be mirrored, stop and ask.
2. **O11 bugs:** list them separately ("suspicious") and let the user choose which to fix. Never fix silently.
3. **Naming:** ask up front whether to keep the O11 names or use new ones. Renaming at the end costs more than starting with the new names.
4. **Never filter with `Index()` on id strings.** Large ids give wrong matches. Use a helper entity or proper joins.
5. **Links to screens not yet in ODC:** a Destination of type External URL with a placeholder value plus a Comment node naming the real O11 target. Never JavaScript or RedirectToURL workarounds.
6. **Roles:** reuse the existing public roles from the core apps. Never create app-local copies.
7. **Business logic lives in the core app**, exposed to the UI as service actions. Client actions can call core service actions directly.
8. **O11 BPT processes → ODC Events** doing the same thing.
9. **Advanced queries:** convert them to PostgreSQL.
10. **SQL injection in table sorting:** fix it with `CASE WHEN` in the `ORDER BY` instead of concatenating the sort column.
11. **The user may edit apps in ODC Studio too.** Before every Mentor publish, check the live revision with `env_app`. If it moved past Mentor's base, ask Mentor to reload the app to that revision and re-apply your changes on top. Don't publish from Mentor and Studio at the same time.

## Core app conventions

- Follow the conventions of the existing core apps in the tenant. Look at them with `context_search` / `context_actions` before inventing names or folders, and ask the user which app to use as the model.
- Put every new service action in a folder, and name the folder in the Mentor prompt.
- ODC action names are limited to **50 characters**.

## Workflow

1. **Read O11.** Open each module you need with the loop above, then dump screens, blocks, actions and the data model with the Service Studio MCP. Condense big dumps into spec files in the scratchpad; they are the checklist you diff against later.
2. **Map dependencies.** For every O11 entity or action used, find its ODC home with `context_search` / `context_entities` / `context_actions`. Ask the user about anything without an obvious home.
3. **Plan in phases** (data model → core service actions → screens → blocks and widgets) and get the user's OK, including the list of unavoidable deviations.
4. **Build through Mentor in batches of about 30 items at most.** Bigger prompts get items silently skipped. One prompt at a time per session.
5. **Verify against O11; don't trust Mentor's "done".** Ask Mentor for a plain-text dump of what it built and diff it against the O11 spec. Check that validation errors are 0.
6. **Publish when asked:** check the live revision → publish → `publish_status` → confirm with `env_app` that the live revision equals the new one → give the URL.

## Mentor mechanics and pitfalls

- `mentor_prompt` returns immediately; wait with a background `sleep 60` (foreground sleep is blocked), then `mentor_get_run` (cursor 0 for the full text; fetch truncated events with `mentor_get_event`). Status `not_found` → resend.
- `OS-IDE-WORKSPACE-40907` ("turn is running") can still have applied the change; check before redoing.
- The tenant context index lags a few minutes after a publish or after exposing tables on a connection, so Mentor won't see new public elements straight away. Wait and retry.
- `OS-BEW/FEW-CODE-40036` on publish usually means a producer library was built against an older OutSystems UI. The fix is to republish that library with OutSystems UI refreshed.
- **A 404 when navigating to a screen usually means the user lacks one of the screen's roles** (ODC shows 404, not a permissions error). Make detail and edit screens allow the same roles as the list screen that links to them.
- ODC has no anonymous records; create a named structure.
- Mentor occasionally touches other loaded apps; check `assetFacts.changeApplied` per asset after every run.
