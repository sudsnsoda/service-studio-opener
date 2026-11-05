# Extraction protocol (Claude Code + Service Studio MCP)

Contents: tools · loop per module · notes format · logic reference format · failure handling · what not to do

## Tools

| Tool | From | Use |
|---|---|---|
| `list_open_modules` | `studio-opener` | Which modules are open as tabs |
| `ensure_module_open(name)` | `studio-opener` | Opens the module through Service Studio's Open dialog if it is not open |
| `activate_module(name)` | `studio-opener` | Brings the module's tab to the front |
| `listApps`, `getRoleNames`, `getDataModel`, `getActionNames`, `getScreenNames` | `servicestudio` | Read-only model reads (confirmed in use) |

Other read tools exist in the Service Studio MCP and in the `servicestudio-mcp-oml` skill. Check that skill for the exact tool list and argument names before assuming one; do not guess tool names.

## Loop per module

1. `ensure_module_open(<Module>)`. Accept `already open` or `<Module> open`; stop on anything else.
2. `activate_module(<Module>)` so the module is the active tab. The Service Studio MCP may act only on the active module.
3. Confirm with `listApps` that the module is loaded.
4. Read, in this order: roles, data model (entities, attributes, relationships), server actions (name, inputs, flow), screens and blocks (name, actions, aggregates), then the logic of actions that hold rules: validation, status transitions, permission checks, notifications, ERP or external calls.
5. Write the notes files immediately (below). Then move to the next module.

Open modules one at a time. Each open goes through the Open dialog and takes the mouse and keyboard.

## Notes format

One folder per application: `docs/<Application>/`.

`<Module>.md`:

```
# <Module>
Layer: UI | Widgets (_CW) | Business logic (_BL) | Core service (_CS) | Integration | Library
Responsibility: <one sentence>
Counts: screens N · blocks N · actions N · aggregates N · entities N
Read on: <YYYY-MM-DD>

## Roles
<role names and what each can do, as read>

## Rules
- <rule in plain language> — where enforced: server | browser only — source: <element name>

## Calls into other modules
- <Module>.<Action> — why

## Not read / unclear
- <what could not be read or is not stated>
```

`SUMMARY.md`: module list with layer and counts, total elements, extraction date, modules called but not opened (with the actions used).

## Logic reference format

`<Module>.ref.json` is a JSON array of `[kind, name, pseudo-code]` entries, one per element. Kinds seen in the Operations page: `Client action`, `Screen action`, `Server action`, `Aggregate`, `Screen`, `Block`. The pseudo-code is one numbered line per flow node in execution order, with branch targets:

```
  1. START -> 2
  2. AGG GetJob FROM Jobs WHERE (Jobs.Id = JobId) MAX 1 -> 3
  3. IF not GetJob.List.Empty T->5 F->4
  4. END
  5. SERVER Job_CS.JobStatus_Set(Id=GetJob.List.Current.Jobs.Id) -> 6
  6. END
```

`build refdata.json` is the object `{ "<Module>": [ ...entries ] }` made by combining the files.

## Failure handling

| Message | Meaning | Action |
|---|---|---|
| `ERROR: Service Studio ... not found` / `not running` | Studio is not reachable by the opener | Stop; report |
| `ERROR: Open dialog did not appear` | Another dialog or prompt is in the way | Stop; ask the user to close it |
| `ERROR: no exact match ...` / `no match ...` | Name wrong or list slow | Stop; confirm the exact module name |
| `ERROR: opened X instead of Y` | A different module opened | Stop; tell the user to close X |
| `TIMEOUT opening X` | Tab never appeared | Stop; report |
| MCP `-32000 Could not find file ...-in.oml` | The MCP's temporary copy of the module is missing | Stop; do not retry. The user checks the temp folder (`%TEMP%\ServiceStudio.MCPServer`), antivirus, pending dialogs, then restarts the MCP server |
| Connection refused / approval prompt | MCP server stopped or an approval is pending | Stop; ask the user to start it (Edit > MCP Server) and approve |

Report the exact text of the failure, which module, and which notes files already exist so the run can resume.

## What not to do

- Never call write tools (`applyModelApiCode`, `omlMerge`, `omlReset`, `omlPublish`).
- Never close tabs or press save, discard or publish in any dialog. Tabs marked `*` may hold unsaved work.
- Never retry in a loop; never open modules in parallel.
- Never document a rule you did not read. Put it under "Not read / unclear".
