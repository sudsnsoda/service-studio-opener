# Page structure and components

Contents: page skeleton · section order and ids · components · known issues and gaps tables · appendix · index card

Everything here mirrors the existing Operations page, so new pages look and behave the same. All styles are in `assets/page-style.css` (inlined by `scripts/assemble.py`); do not add new CSS unless a component truly has no equivalent.

## Page skeleton (`body.html`)

```html
<div class="wrap">
<nav class="toc">
  <div class="brand">Meivworld Business Logic</div>
  <div class="grp">Guide</div>
  <a href="#start">Before you start</a>
  <!-- one <a> per section; a.sub for h3 level inside a page section -->
</nav>
<main>
  <header class="hero">
    <div class="eyebrow">Meivworld Business Logic · OutSystems 11</div>
    <h1><Application name></h1>
    <p class="lede">What every page, tab and button does, who can use it, when it is available and what the system does when you use it. The rules were read from the application models in Service Studio, not from the screens’ text. The developer reference is in the <a href="#appendix">appendix</a>.</p>
    <div class="facts">
      <div><b>N</b>pages</div><div><b>N</b>user actions</div>
      <div><b>N</b>modules read</div><div><b>D Mon YYYY</b>extracted</div>
    </div>
    <div class="toolbar">
      <button type="button" id="techToggle" aria-pressed="false">Show technical names</button>
      <span>Adds the Service Studio element behind each action, for developers.</span>
    </div>
  </header>
  <!-- sections -->
  <!-- reference section from assets/reference-section.html, last -->
</main>
</div>
```

Facts come from the extraction notes. Count only what was read.

## Section order and ids

Group labels in the nav: Guide, Behind the scenes, Appendix. Each `h2` carries a crumb naming its group.

| Group | id | Content |
|---|---|---|
| Guide | `start` | Before you start: what the app is for, key terms, tenant or scoping rules, roles, who can see what, statuses/lifecycle |
| Guide | one per screen (`p-...`) | One `h2` per page (crumb "Page"), one `h3` per tab or section, each `h3` with an `id` (`t-...`) |
| Guide | `rules` | Rules enforced by the system, split into server-enforced and browser-only, and effect of lifecycle events |
| Behind the scenes | `auto` | Automatic processes (timers, queues), grouped by purpose |
| Behind the scenes | `integrations` | External systems and sync: which actions sync, call logs |
| Behind the scenes | `issues` | Known issues table |
| Behind the scenes | `gaps` | Not yet documented table |
| Behind the scenes | `method` | About this guide: which modules and how many elements were read, read-only |
| Appendix | `appendix`, `architecture`, `modules`, `hidden`, `reference` | Developer reference, layer table, logic per module (`h3` per module), modules not yet open, searchable logic reference |

Drop sections that do not apply (an app with no timers has no `auto`), but keep `issues`, `gaps` and `method`: an empty "Known issues" is itself a finding only if it was looked for.

## Components

Heading with UI label:
```html
<h3 id="t-budgeting">Budgeting tab <span class="pt">Orçamentação</span></h3>
<div class="meta"><span>Opens with <b>Role Name</b></span><span>Menu: App -> Entry</span><span class="tech">Module.ScreenName</span></div>
```

Action table (one row per user action):
```html
<div class="tablewrap"><table class="acts">
<thead><tr><th>Action</th><th>Who</th><th>When available</th><th>What happens</th></tr></thead>
<tbody><tr>
  <td><span class="btn">Confirm</span><span class="en">Confirmar</span><span class="tech">Module.Block.ConfirmClick</span></td>
  <td><span class="role">Manager</span><span class="role exact">Admin</span></td>
  <td>Job is Planning or Running.<span class="cond">Hidden once the job is closed.</span></td>
  <td>Sets the status to Running and notifies the team.</td>
</tr></tbody></table></div>
```
`role.exact` (adds ✱) marks a role matched on the exact level rather than "level or above"; explain the ✱ once in `start`. Use `<span class="btn danger">` for destructive actions.

Other blocks: `.pop` for what a pop-up shows (`<span class="pop">` with a `<ul>`); `.note` for a caution (starts with `<strong>`); `.callout` for a rule people usually get wrong (starts with `<strong>`); `.gap` for something not stated in the source; `q.msg` for message text shown to users; `<span class="st">Running</span>` for a status name.

## Known issues and not-yet-documented tables

Known issues:
```html
<div class="tablewrap"><table>
<thead><tr><th>Impact</th><th>What you may notice</th><th>Where</th></tr></thead>
<tbody><tr><td><span class="sev high">High</span></td><td>...</td><td>...</td></tr></tbody></table></div>
```
Sort by impact (high, med, low), then by area. State the counts in the intro paragraph and make them match the rows.

Not yet documented: a two-column table (area, what was not read, with `<span class="tech">` module names). Order by importance to the business.

## Appendix: modules not yet open

Columns: Module · Priority · Actions used · Call sites · Server actions called. Priority uses `<span class="tier t1">Next</span>` or `t2` ("Then"), and the row gets class `t1`/`t2`. Each called action is `<code title="called from: ModuleA, ModuleB">ActionName</code>`.

## Index card (added to the index artifact)

The index lists applications in a `div.apps`. Add one anchor per application:

```html
<a class="app" href="https://claude.ai/artifact/<new-id>">
  <div>
    <h3>Application name (Portuguese name)</h3>
    <p>One or two sentences on what the application covers.</p>
  </div>
  <span class="status">Documented</span>
  <div class="meta"><span>Main module <b>Main_Module</b></span><span><b>N</b> modules</span><span><b>N</b> elements extracted</span><span>Extracted <b>D Mon YYYY</b></span></div>
  <div class="mods"><span>Module_A</span><span>Module_B</span></div>
  <span class="open">Open documentation →</span>
</a>
```

Edit the index with `Artifact` action `edit` (old_str/new_str copied exactly from the file read first), then re-read to confirm the card is present. The index also has a "Next: core logic" table of modules still to document; remove or reword rows for modules the new page now covers.
