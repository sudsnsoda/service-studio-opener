---
name: meivworld-business-logic-docs
description: Document the business logic of Meivworld OutSystems 11 applications from Service Studio models, and publish it as a page in the "Meivworld Business Logic" artifact library. Use whenever the user asks to document, extract, read or explain the logic of an OutSystems module or application (Operations, Purchases, HR, OSH, Requests, any *_CS / *_BL / *_CW module), to add an application to the Meivworld Business Logic index, to update an existing documentation page, or mentions ensure_module_open, the servicestudio MCP, or the modules listed under "Next core logic" in the index. Covers both halves of the job, which are read-only extraction in Claude Code and building and publishing the artifact page in claude.ai.
---

# Meivworld business-logic documentation

The library is one index artifact plus one page per application. A page explains, in plain language, what every screen, tab and button does, who can use it, and what the server actually enforces, with a developer appendix behind it. Rules come from the Service Studio models, not from screen text, so the page describes what the app enforces rather than what labels suggest.

- Index: the library's index artifact. Ask the user for its link if it is not in the conversation.
- Reference page to match: an existing application page from the library, whose link the user provides. It can be several MB because of the embedded logic reference because of the embedded logic reference, so never open it whole. Search it with grep or Python, or rely on `assets/` and `references/page-structure.md`, which already capture its structure and styles.

## Step 0: decide which half you are doing

Check which tools this session has before doing anything else.

| Tools present | Mode | Do this |
|---|---|---|
| `ensure_module_open` / `list_open_modules` and the Service Studio MCP (`getDataModel`, `getRoleNames`, ...) | Extraction | Read `references/extraction-protocol.md` and follow it. Write notes to files; do not build the page here. |
| `Artifact` tool (claude.ai) and extraction notes the user attached or that exist in the workspace | Build | Read `references/page-structure.md`, then follow "Build mode" below. |
| Neither | Stop | Say which half is missing and what the user needs to provide. Do not invent logic. |

If the user wants the whole job in one place and only the Build tools exist, ask for the extraction folder (`docs/<Application>/`). If only the Extraction tools exist, produce the notes and tell the user to attach them in claude.ai.

## Extraction mode (summary)

The full rules are in `references/extraction-protocol.md`. The ones that matter most:

1. Read only. Never call `applyModelApiCode`, `omlMerge`, `omlReset` or `omlPublish`; a documentation run must leave every module exactly as it was.
2. One module at a time: `ensure_module_open(X)`, then `activate_module(X)`, then read. Use exact module names (letters, digits, underscore).
3. Write notes per module straight after reading it, so a long run survives a full context window.
4. On any `ERROR`, `TIMEOUT`, or MCP error (including `-32000 ... -in.oml`), stop and report the exact text. Do not retry in a loop.

## Build mode

1. Gather inputs: the application name, its main module, every module's notes file, the extraction date, and the element counts. Counts and dates in the hero come from the notes; never estimate them.
2. Read `references/page-structure.md` for section order, ids, and the HTML components, then write `body.html` (the `<div class="wrap">` with `nav.toc` and `<main>`). Follow the writing rules below.
3. Build `refdata.json` from the per-module `.ref.json` files (format in `references/extraction-protocol.md`) and assemble the page:
   ```
   python scripts/assemble.py --title "<Application name> Business Logic" \
     --body body.html --refdata refdata.json --out /mnt/user-data/outputs/<slug>/index.html
   ```
   The script inlines `assets/page-style.css` and both scripts, and escapes the data so it cannot close the script tag. If there is no logic reference yet, omit `--refdata` and leave the reference section out of the body.
4. Publish a new artifact from that file with the `Artifact` tool (no `url`, so the existing page is not overwritten). Keep the same favicon across republishes.
5. Add a card for the new page to the index with `Artifact` action `read` on the index URL, then `edit` with the card markup from `references/page-structure.md`. Also update the index's "Next" table: remove or reword the rows for modules that are now documented.
6. Report the new link, the counts, what is listed under "Not yet documented", and anything that could not be verified.

## Writing rules

- **Describe behaviour, not implementation, in the guide; put implementation in the appendix.** Technical names go in `<span class="tech">` so the page's "Show technical names" toggle can reveal them.
- **Every rule must trace to something read.** If the models do not say it, do not write it. Use a `.gap` block instead, stating exactly what is missing ("whether the export is limited to the rows on screen is not stated in the source").
- **Say where enforcement happens.** Distinguish rules the server enforces from checks that run only in the browser; the Operations page has a dedicated section for the second kind because it is where real risk hides.
- **Known issues are findings, not opinions.** List behaviour that looks unintended (for example a role compared by Id instead of Level), with impact (`sev high|med|low`) and where the user would notice it. Do not pad the list.
- **Bilingual labels.** The app UI is Portuguese. Give the English heading and the UI label in `<span class="pt">`. Copy the Portuguese label from the model; if you did not read it, leave it out rather than translating from memory.
- **Plain language first.** A sentence per rule, conditions stated exactly ("when the start date is today or earlier"), no pseudo-code in the guide.
- **Typography.** Use ’ for apostrophes and « » for Portuguese quotes inside `q.msg`, as in the existing pages.

## Before publishing

Spot-check three or four rules against the notes (and, if the user can, against Service Studio). Generated documentation states wrong behaviour as confidently as right behaviour, so say in the report which claims were verified and which were not.
