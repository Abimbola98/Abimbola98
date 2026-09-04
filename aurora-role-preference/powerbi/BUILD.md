# Aurora Preference — Power BI Desktop build walkthrough

Click-level assembly instructions. `README.md` is the *spec* — what the model is
and why. This is the *procedure* — what to click, in what order, and what to
type into each field well.

**Read §0 first.** It records three constraints already baked into the query
files — a table that exists only to carry a parameter, why role names are
resolved in M rather than by relationships, and one number on page 4 that is a
bound rather than a count.

Two honest caveats before you start:

- **None of this has been run.** The M and DAX are written against documented
  Power Query and DAX behaviour and reviewed, but no one has executed them in
  Desktop. Expect first-run errors — a wrong logical-name prefix, a column that
  comes back typed differently than assumed. That is the expected path, not a
  sign the model is wrong.
- **Desktop's menus move between releases.** Where a click path below does not
  match your build, the field-well contents and the settings still apply; only
  the route to them changed.

Realistically: two to three hours to the end of §6, then an hour or so per page.

---

## 0. What changed in the query files, and why

An earlier draft of this walkthrough listed three things that would stop the
build. All three are now fixed in `queries/` and `measures.dax`. They are
recorded here because each one constrains how you build, and because the
reasoning is easy to undo by accident.

### A. `WhatIfSeedValue` — a table that exists only to carry a parameter

DAX cannot read a Power Query parameter. Parameters are scalars; they never
reach the model as tables, so the original
`SELECTEDVALUE ( WhatIfSeed[WhatIfSeed], 1 )` had nothing to bind to and the
`What If Caveat` measure would not have saved.

`02-whatif-assignment.m` now defines a one-row `WhatIfSeedValue` query, and the
measure reads `WhatIfSeedValue[Seed]`. **Let this query load** — unlike the other
staging queries — and give it **no relationships**. It is a caption lookup.

### B. Role names are resolved in Power Query, not by relationships

`PreferenceWide` and `WhatIfAssignment` hold role *keys*; pages 2 and 4 show role
*names*. Relationships cannot bridge that: only one active path is allowed
between two tables, so three key columns pointing at `DimRole` would need three
inactive relationships plus a `USERELATIONSHIP` measure each, returning text into
a table visual — which behaves badly.

`PreferenceWide` now merges `DimRole` three times and emits `Pref1Name`,
`Pref2Name`, `Pref3Name`. `WhatIfAssignment` inherits those three for free (the
allocation fold spreads each person's whole record into its output row) and adds
one merge of its own for `AssignedRoleName`.

**Two nulls that must not look alike**, and the queries keep them apart:

| Situation | Cell shows | Means |
|---|---|---|
| key is null | *(blank)* | fewer than three eligible roles — nothing to show |
| key present, no match in `DimRole` | `(unknown role)` | **broken join** — go to page 6 |
| `AssignedRoleKey` null | `Unassigned` | the fold found no free post — the point of page 4 |

That first row is not an edge case. The app makes people rank **every** role they
are eligible for — `scrForm` blocks submit unless all of `colRanks` carries a
distinct rank — so anyone eligible for one or two roles genuinely has no third
preference.

### C. `README.md` §3 was missing three relationships

`PreferenceWide` was absent entirely (page 2's slicers would have filtered
nothing), as was `WhatIfRoleFill`, and the two deliberately unrelated tables were
not called out. §3 now carries all of it, and §4 below matches.

### One thing still open, by choice

`PreferenceWide` keeps only ranks 1–3, and the what-if models only those. Since
people rank every eligible role, someone whose top three are full comes out
`Unassigned` even where they ranked a fourth role that still had room.
**`Pct Unassigned` is therefore a pessimistic bound, not a headcount.** Widening
it is a one-line change to `PreferenceWide`'s `Top3` step plus a variable-length
pick loop in the fold. Worth doing if that number turns out to drive a decision;
not worth doing speculatively.

## 1. Create the file and the parameters

1. Power BI Desktop → **File > New** (or the **Blank report** card).
2. **File > Save as** → save it before anything else, somewhere backed up. A
   `.pbix` with an hour of query work and no save is a bad afternoon.
3. **Home > Transform data** → the Power Query Editor opens.
4. **Home > Manage Parameters > New Parameter**. Create three:

| Name | Type | Suggested values | Current value |
|---|---|---|---|
| `EnvUrl` | Text | Any value | your Dataverse environment URL, e.g. `https://org12345.crm11.dynamics.com` |
| `CapacityPath` | Text | Any value | the full path/URL to `roles_capacity.csv` — see below |
| `WhatIfSeed` | Whole number | Any value | `1` |

**On `CapacityPath`, decide now, not later.** A local path (`C:\Users\...`)
works on your machine and nowhere else, and refreshing it in the Service needs
an on-premises data gateway. Put the CSV in the team's SharePoint site and both
problems go away, along with "only one person can edit the post counts".

If you use SharePoint, the CSV query's `File.Contents(CapacityPath)` must become
`Web.Contents(CapacityPath)`, and `CapacityPath` must be the **direct file URL**
(SharePoint: open the file's ⋯ menu → Details → Path), not the browser address
you get from "Copy link" — that one is a redirect and returns HTML.

---

## 2. Paste the queries

For each block: **Home > New Source > Blank Query**, then **Home > Advanced
Editor**, select all, paste, **Done**, then rename the query in the Queries pane
on the left (right-click > Rename, or F2). The name must match exactly — later
queries reference earlier ones by name.

Order matters. Work down this table.

| # | Query | From file | Load? |
|---|---|---|---|
| 1 | `CapacityCsv` | `01-sources.m` | **Disable** |
| 2 | `AppRoles` | `01-sources.m` | **Disable** |
| 3 | `DimRole` | `01-sources.m` | Load |
| 4 | `People` | `01-sources.m` | Load |
| 5 | `Preferences` | `01-sources.m` | Load |
| 6 | `Responses` | `01-sources.m` | Load |
| 7 | `Alignments` | `01-sources.m` | Load (or disable — see below) |
| 8 | `RejectReasonsUnpivoted` | `01-sources.m` | Load |
| 9 | `PreferenceWide` | `01-sources.m` | Load |
| 10 | `RoleReconciliation` | `01-sources.m` | Load |
| 11 | `WhatIfSeedValue` | `02-whatif-assignment.m` | Load |
| 12 | `WhatIfAssignment` | `02-whatif-assignment.m` | Load |
| 13 | `WhatIfRoleFill` | `02-whatif-assignment.m` | Load |
| 14 | `StopWords` | `03-textanalysis.m` | **Disable** |
| 15 | `WordFrequency` | `03-textanalysis.m` | Load |
| 16 | `ThemeKeywords` | `03-textanalysis.m` | **Disable** |
| 17 | `ResponseThemes` | `03-textanalysis.m` | Load |

**To disable load:** right-click the query in the Queries pane → untick **Enable
load**. Its name goes italic. Do this for `CapacityCsv`, `AppRoles`, `StopWords`
and `ThemeKeywords`. They are staging — loading them gives you three role tables
and two junk tables, and every "which role table do I use?" question after that
is self-inflicted.

**If the Alignments table does not exist in Dataverse yet,** query 7 will error.
Do not delete it — right-click → untick **Enable load**. The alignment page then
shows blanks instead of the whole model failing to refresh. `RejectReasonsUnpivoted`
reads `Alignments`, so disable that one too until the table exists.

**Do not click Close & Apply yet.** §3 first.

---

## 3. Dataverse: Import, and then the table names

### Import, not DirectQuery — and it is not really a choice

Take **Import**. DirectQuery is not a worse option for this model, it is an
impossible one, and it is worth knowing why before someone suggests it later.

Three things in `queries/` cannot run in DirectQuery at all:

- **`DimRole` is a cross-source merge.** It is a full outer join between
  Dataverse and a CSV. A merge has to fold to a source, and no source can see
  both. In a composite model the Dataverse tables would be DirectQuery and the
  CSV Import, and the merge step is simply not available across that boundary.
  `DimRole` is the spine of the model — no `DimRole`, no relationships, no report.
- **`WhatIfAssignment` is a `List.Accumulate` fold.** Sequential capacity
  decrement, evaluated row by row in the mashup engine. There is no SQL for it
  to fold to.
- **`WordFrequency` and `ResponseThemes`** split text into lists, expand them to
  rows, and anti-join a hardcoded stopword table. Same problem.

Import is also simply the right answer here. The data is tiny — ~111 people, 66
roles, a few hundred preference rows, ~100 free-text answers — and DirectQuery
exists to avoid moving data you cannot afford to move. Several measures would
also be brutal against the TDS endpoint: `Aligned Outside Top 3` runs a `FILTER`
over `Alignments` with a nested `FILTER` over `Preferences`, and
`Roles Oversubscribed` iterates `VALUES ( DimRole[RoleKey] )` evaluating measures
per role. In Import those are trivial. And nothing here needs live data — this is
a process that runs over weeks, so a scheduled refresh is more freshness than any
of the decisions need.

**The one real argument for DirectQuery, and why it fails.** DirectQuery leaves
no data at rest in the semantic model, which is a genuine information-governance
point for OFFICIAL SENSITIVE free text about people's jobs. It does not survive
contact: the CSV half cannot be DirectQuery regardless so you would store data
anyway; the Service caches visual results, so "nothing is stored" was never true;
and the actual control is workspace membership, not storage mode. A DirectQuery
report published to a wide audience leaks exactly as much as an Import one. Do
not let storage mode stand in for restricting the workspace — see §8.

In practice, M pasted by hand into a blank query lands in Import; the DirectQuery
option is offered through the Navigator UI. If you are ever asked to choose, take
Import, and do not go looking for the toggle.

One consequence to plan for: **`WhatIfSeed` is a Power Query parameter, so
changing the seed is a refresh, not a slicer click.** That is inherent to doing
the allocation in M. If you want seed-switching without a refresh, that is a
different design — precompute several seeded runs into one table and put a real
what-if slicer over them.

### The names are already correct for this environment

`queries/01-sources.m` carries the real `cr174_` names for
`orgb83df62a.crm11.dynamics.com`, checked column by column against the
environment and confirmed against the data. Nothing to do here unless you are
building against a different environment — in which case the prefix and several
names differ, and **`README.md` §3 "Dataverse column names, and the three that
lie" is the map you need**, because two tables are not just a prefix swap and
three columns do not hold what their logical names say.

The short version of what the queries handle for you:

| What | Why it would have broken |
|---|---|
| `cr174_employeeidrolekey` → `EmployeeID` (Preferences, Responses) | there is no `cr174_employeeid` on either table; the join to `People` would match nothing and every page would read empty with no error |
| `cr174_gradeareateam` → `Grade` (People) | there is no `cr174_grade`; the grade slicer and `Total Line Managers` would have no field |
| `Decision` is `Accepted` / `Rejected` | comparing against `Accept` / `Reject` returns zero, so page 5 reads "nobody challenged anything" while challenges sit in the table |
| `Active` / `IsAdmin` are Yes/No | declared `type logical`, they fail the refresh outright if TDS returns `0`/`1` |

Model field names match the Dataverse display names one-for-one, so a field on a
visual can be traced straight back to a column in the table. The single
exception is `Roles.RoleName` → `AppRoleName`, which exists to keep the `DimRole`
merge readable against the CSV's own `RoleName`.

### One thing to settle with the business, not in Desktop

`People[IsLineManager]` drives the `Total Line Managers` card, and the query
matches grades `G6` and `G7` because that is what the brief says. **The grades
actually in this app are `SG5`, `SG6` and `G7`** — Environment Agency staff
grades, where `SG6` is not self-evidently the same thing as `G6`. As written,
the card will count only the `G7`s.

That is a business question, not a code one. The list is a named step at the top
of the `People` query (`MgrGrades`) so it is one edit once somebody answers.

### Then apply

**Home > Close & Apply.** Expect a minute or two. Errors at this point are
almost always a name that does not match, not broken logic — read the message,
fix the name, re-apply.

---

## 4. Relationships

Left rail → **Model view** (the third icon). Drag the *from* column onto the
*to* column to create each relationship. Then double-click the line and check
the cardinality, direction and active state against this table.

| From (one side) | To (many side) | Cardinality | Cross-filter | Active |
|---|---|---|---|---|
| `People[EmployeeID]` | `Preferences[EmployeeID]` | 1 → * | Single | ✔ |
| `People[EmployeeID]` | `Responses[EmployeeID]` | 1 → * | Single | ✔ |
| `People[EmployeeID]` | `Alignments[EmployeeID]` | 1 → * | Single | ✔ |
| `People[EmployeeID]` | `WhatIfAssignment[EmployeeID]` | 1 → * | Single | ✔ |
| `People[EmployeeID]` | `RejectReasonsUnpivoted[EmployeeID]` | 1 → * | Single | ✔ |
| `People[EmployeeID]` | **`PreferenceWide[EmployeeID]`** | 1 → * | Single | ✔ |
| `People[EmployeeID]` | `ResponseThemes[EmployeeID]` | 1 → * | Single | ✔ |
| `DimRole[RoleKey]` | `Preferences[RoleKey]` | 1 → * | Single | ✔ |
| `DimRole[RoleKey]` | `Responses[RoleKey]` | 1 → * | Single | ✘ **inactive** |
| `DimRole[RoleKey]` | `Alignments[AssignedRoleKey]` | 1 → * | Single | ✘ **inactive** |
| `DimRole[RoleKey]` | `WhatIfAssignment[AssignedRoleKey]` | 1 → * | Single | ✘ **inactive** |
| `DimRole[RoleKey]` | `WhatIfRoleFill[RoleKey]` | 1 → * | Single | ✔ |

Without the `PreferenceWide` row the Area/Grade/Team slicers on page 2 filter
nothing. It is easy to miss because `PreferenceWide` has no obvious fact-table
shape.

**Tables with no relationships, deliberately:**

- `WordFrequency` — pre-aggregated to one row per word. It has no `EmployeeID`
  and cannot be filtered by anything. Use it alone on the word cloud; do not put
  a slicer next to it and expect the cloud to respond.
- `WhatIfSeedValue` — a one-row caption lookup.
- `_Measures` — see §5.

**To make a relationship inactive:** double-click the line → untick **Make this
relationship active** → OK. Desktop draws inactive relationships as a dashed
line. Only one active path is allowed between any two tables, so Desktop will
refuse to activate the second `DimRole` → *fact* relationship anyway; make sure
the one it kept active is `Preferences`, because that is what the whole demand
analysis runs on.

**`Preferences[RoleKey]` may fail with "column contains duplicate values".** That
error is on the *`DimRole`* side, not `Preferences` — it means `DimRole[RoleKey]`
is not unique. `01-sources.m` ends `DimRole` with `Table.Distinct(Fam, {"RoleKey"})`
to guarantee it, so if this fires, something upstream produced a null key on both
sides of the merge. Go to page 6 (§7) before doing anything else.

**Hide what nobody should pick up.** Right-click → **Hide in report view** on:
`People[Email]`, `People[IsAdmin]`, every `RoleKey`/`EmployeeID` on the fact
tables (keep `People[EmployeeID]` and `DimRole[RoleKey]` visible — page 2 shows
the employee ID and page 6 shows the role key). A field list nobody can navigate
is the main reason report pages get built against the wrong column.

---

## 5. The measures table

1. **Home > Enter data**. Leave the single empty `Column1`. Name the table
   `_Measures`. **Load**.
2. In the Data pane, right-click `_Measures` → **New measure**. Paste one
   measure from `measures.dax`, press ✓. Repeat.

There is no bulk paste in Desktop. It is 45-odd measures one at a time, which is
tedious — if you do this often, **Tabular Editor** (free, external tool) pastes
them all in one go and is worth the twenty minutes to set up.

Take them in file order: the later ones reference the earlier ones by name, and
Desktop will not accept `[Total Colleagues]` before that measure exists.

`What If Caveat` reads `WhatIfSeedValue[Seed]`, so query 11 must be loaded
before that measure will save.

Once the first measure lands, right-click `_Measures[Column1]` → **Hide in
report view**. (Do not try to delete it — a table needs at least one column.)
The table icon changes to a calculator and, with the leading underscore, sorts
to the top of the Data pane.

### Format strings — do this, it is not cosmetic

Select each measure → **Measure tools** ribbon → set the format. Left alone,
`Completion Rate` renders as `0.87` on a card and every percentage on the report
is wrong-looking.

| Measures | Format | Decimals |
|---|---|---|
| `Completion Rate`, `Pct Got 1st/2nd/3rd Choice`, `Pct Unassigned`, `Pct Got Any Choice`, `Acceptance Rate`, `Challenge Rate`, `Pct Mentioning Theme`, `Pct Of Challenges Citing Reason` | Percentage | 0 |
| `People Per Post`, `Subscription Ratio`, `Reasons Per Challenge` | Decimal number | 2 |
| everything else | Whole number | 0 |

---

## 6. Report-level settings

**File > Options and settings > Options > Current file**:

- **Report settings > Export data** → *Allow end users to export data from this
  report* (summarized **and** underlying). PAB-6119's real ask is almost always
  "can I get this into Excel"; without this the table page is a dead end.
- **Data Load** → untick *Auto date/time for new columns*. Nothing here needs a
  date hierarchy and it adds a hidden table per date column.

---

## 7. The pages

Seven pages. Rename each tab as you create it (double-click the tab).

Throughout: **Visualizations pane** to pick a visual, then drag fields from the
Data pane into the wells. `[square brackets]` below means a measure from
`_Measures`; `Table[Column]` means a column.

### Page 1 — Preference process summary

**Cards** (Card visual, one field each) across the top:
`[Total Colleagues]`, `[Total Areas]`, `[Total Teams]`, `[Total Line Managers]`,
`[Total Roles Available]`, `[Total Posts]`, `[Completion Rate]`,
`[People Per Post]`.

**Stacked column chart — role distribution by area**
- X-axis: `People[Area]`
- Legend: `DimRole[RoleFamily]`
- Y-axis: `[Applications]`

Family, not individual role — the legend would otherwise carry 66 entries.
Expect an **`(unknown)`** bucket: `RoleFamily` comes only from the capacity
sheet, so any app-only role lands there. If that bucket is large, page 6 will
tell you why.

**Donut — where people are in the process**

Needs a calculated column that does not exist yet. Right-click `People` → **New
column**:

```
Process Stage =
VAR e = People[EmployeeID]
VAR ranked = CALCULATE ( COUNTROWS ( Preferences ), ALLEXCEPT ( People, People[EmployeeID] ) )
VAR submitted =
    CALCULATE (
        COUNTROWS ( Responses ),
        ALLEXCEPT ( People, People[EmployeeID] ),
        Responses[Stage2Status] = "Submitted"
    )
RETURN
    SWITCH ( TRUE (), submitted > 0, "Completed", ranked > 0, "In progress", "Not started" )
```

- Legend: `People[Process Stage]`
- Values: `[Total Colleagues]`

**Slicers**: three Slicer visuals — `People[Area]`, `People[Grade]`,
`People[Team]`. Format > Slicer settings > Options > Style: **Dropdown** for
Team (there will be a lot of them), Vertical list is fine for Area and Grade.

> The wireframe shows a 100% completion card. Point it at `[Completion Rate]`
> and let it say what it says — at the time of writing the app had 1 of 111.

### Page 2 — Respondent table (PAB-6119)

One **Table** visual filling the page. Columns, in order:

`People[Name]`, `People[EmployeeID]`, `People[Grade]`, `People[Area]`,
`People[Team]`, `PreferenceWide[Pref1Name]`, `PreferenceWide[Pref2Name]`,
`PreferenceWide[Pref3Name]`, `PreferenceWide[SubmittedOn]`, and once Phase 2
data exists `Alignments[AssignedRoleKey]` and `Alignments[Decision]`.

Rename the column headers in the visual (double-click the header in the Values
well, or Format > Column headers): `Pref1Name` → *Preference 1*, and so on. The
underlying names stay as they are.

A blank `Preference 3` means the person had fewer than three eligible roles;
`(unknown role)` means a broken join — see §0.B and page 6.

**Slicers** down the right: `People[Area]`, `People[Grade]`, `People[Team]`,
`Responses[Stage2Status]`. Plus a **search on Name** — the built-in way is
Format > Slicer settings > Options > **Search** on a `People[Name]` slicer.

**Export**: with §6 done, the visual's ⋯ menu shows *Export data*. Test it here.

### Page 3 — Over and undersubscribed roles

**Matrix — the heatmap.** The README sketch puts `Preferences[Rank]` on Columns
*and* `Posts For Role` / `Subscription Ratio` in Values. Do not do that: with a
Columns grouping, **every** value measure repeats under every rank, so you get
"Posts For Role" three times and a matrix nobody can read. Use no Columns field:

- Rows: `DimRole[RoleName]`
- Columns: *(empty)*
- Values: `[First Choices]`, `[Second Choices]`, `[Third Choices]`,
  `[Posts For Role]`, `[Subscription Ratio]`, `[Oversubscription]`

One row per role, the rank split still visible, and the supply columns appear
once. If you specifically want the rank matrix as well, make it a **second**
matrix with only `[Applications]` in Values.

**Conditional formatting on `Subscription Ratio`:** select the matrix → Format
pane → **Cell elements** → *Series*: `Subscription Ratio` → **Background color**
→ On → **fx**:

- Format style: **Gradient**
- Minimum: **Number**, `0`, colour blue
- ✔ **Add a middle color**: **Number**, `1`, colour white
- Maximum: **Number**, `3`, colour red

White at exactly filled, blue below, red above. `3` as the maximum rather than
"Highest value" keeps the scale stable between refreshes — otherwise one extreme
role rescales everything else to near-white.

**Zero-post roles come back blank, not red.** `Subscription Ratio` uses `DIVIDE`,
which returns BLANK on a zero denominator rather than infinity. That is
deliberate — an unfillable role is not "infinitely popular" — and it is why
`[Roles With Zero Posts]` is a separate card. R16 is the current example.

**Cards**: `[Roles Oversubscribed]`, `[Roles With No Interest]`,
`[Roles With Zero Posts]`, `[Roles Not Reconciled]`.

**Bar chart — most contested**
- Y-axis: `DimRole[RoleName]`
- X-axis: `[Oversubscription]`
- Filters pane → *Y-axis* → Filter type **Top N**, Show items: Top `10`, By
  value `[Oversubscription]`.

**Link `Roles Not Reconciled` to page 6.** Select the card → Format → **Action**
→ On → Type: **Page navigation** → Destination: page 6. A heatmap that quietly
drops three roles because they have no key is worse than one that says so.

Optionally keep the wireframe's role × area heatmap as a second matrix:
Rows `DimRole[RoleName]`, Columns `People[Area]`, Values `[Applications]`.

### Page 4 — What if everyone got their first choice

**Cards**: `[Pct Got 1st Choice]`, `[Pct Got 2nd Choice]`, `[Pct Got 3rd Choice]`,
`[Pct Unassigned]`, `[Posts Unfilled]`.

**Table** — the wireframe's layout, straight off `WhatIfAssignment`:
`People[Name]`, `WhatIfAssignment[Pref1Name]`, `[Pref2Name]`, `[Pref3Name]`,
`WhatIfAssignment[AssignedRoleName]`.

Conditional-format the assigned column: Format → **Cell elements** → Series:
`AssignedRoleName` → **Background color** → fx → Format style: **Rules**, Based
on field: `WhatIfAssignment[OutcomeRank]`, Summarization: **Maximum**:

| If value | | | Then |
|---|---|---|---|
| `is` `1` | to | `1` | green |
| `is` `2` | to | `2` | amber |
| `is` `3` | to | `3` | orange |
| `is` `0` | to | `0` | grey |

**Stacked bar of the four outcomes**: Y-axis `WhatIfAssignment[Outcome]`, X-axis
`[Modelled People]`. (A funnel works too but sorts by value, which puts the
outcomes in an order that changes between seeds — the bar is steadier.)

**Bar, roles left unfilled**: Y-axis `WhatIfRoleFill[RoleName]`, X-axis
`WhatIfRoleFill[PostsUnfilled]`, sorted descending, Top N 10.

**A text box carrying `[What If Caveat]`.** Not optional, and it has to be a
**Card** visual rather than a literal text box, because a text box cannot hold a
measure. Set the card's title off and let the measure text carry it. One run is
one shuffle; whoever reads this page needs to know the individual rows are not
decisions.

**Then test the stability.** Home > Transform data > Manage Parameters, set
`WhatIfSeed` to 2, Close & Apply, note `[Pct Got 1st Choice]`. Repeat for 3 and
4. If the headline moves a couple of points, the shape is real. If it swings
ten, **that instability is the finding** and belongs on the page, not in your
head.

### Page 5 — Alignment: accepted and challenged

Blank until the Alignments table exists in Dataverse. That is expected.

**Cards**: `[Alignments Published]`, `[Decisions Made]`, `[Awaiting Decision]`,
`[Acceptance Rate]`, `[Challenge Rate]`, `[Aligned Outside Top 3]`.

**Bar — why people challenged**
- Y-axis: `RejectReasonsUnpivoted[Reason]`
- X-axis: `[Reason Mentions]`
- Tooltips: `[Pct Of Challenges Citing Reason]`

Reasons are multi-select, so those percentages sum past 100 **by design**. Put
`[Reasons Per Challenge]` on the page as a card so the reader can see why.

**Table of challenges**: `People[Name]`, `People[Area]`,
`Alignments[AssignedRoleKey]`, `Alignments[RejectReasons]`,
`Alignments[RejectComments]`. Filter the visual: Filters pane → this visual →
`Alignments[Decision]` is `Reject`.

`[Aligned Outside Top 3]` is the number most likely to predict a challenge —
give it a card of its own rather than burying it in the row.

### Page 6 — Source reconciliation

**Check this page before you trust any other.** Build it early.

**Table** on `RoleReconciliation`: `RoleKey`, `RoleName`, `Posts`, `JoinStatus`.

**Cards**: `[Roles Missing A Key]`, `[Roles Missing From The App]`,
`[Roles Missing A Post Count]`, `[Preferences For Unknown Role]`.

What the numbers should say on a healthy first run, given the known data
problems in `README.md` §5:

| Card | Expected today | If it differs |
|---|---|---|
| `Roles Missing A Key` | **3** — the `?` rows, keyed `NOKEY-01/02/03` | the CSV changed |
| `Roles Missing From The App` | **1** (R08) — or **0** once R08 is added to Dataverse | a new role is in the sheet but not the app |
| `Roles Missing A Post Count` | **0** | an app role is not in the capacity sheet; nobody can be allocated to it |
| `Preferences For Unknown Role` | **0** | somebody ranked a role that has since been deleted — investigate before anything else |
| `Total Posts` (page 1) | **80** | see §5.4 of the README: it may be overstated by 4 |

`Preferences For Unknown Role` above zero means the join is broken and every
number on page 3 is understated. Nothing else on this report is trustworthy
until it reads zero.

### Page 7 — Themes in the free text

**Word cloud**: the *Word Cloud* visual comes from AppSource (⋯ in the
Visualizations pane → **Get more visuals**). Check it is available and permitted
in your tenant — custom visuals are often blocked by admin policy, and this one
has moved in and out of AppSource. **Fallback if it is not available:** a bar
chart, Y-axis `WordFrequency[Word]`, X-axis `WordFrequency[People]`, Top N 25.
Less pretty, more readable, no tenant approval needed.

- Category: `WordFrequency[Word]`
- Values: `WordFrequency[People]` — **not** `[Frequency]`. One person writing
  "flood" eleven times should not outrank eleven people writing it once.

**Bar — themes**: Y-axis `ResponseThemes[Theme]`, X-axis `[Pct Mentioning Theme]`.

**Cards**: `[Answers Written]`, `[Median Answer Length]`, `[Answers At The Limit]`.

If `Answers At The Limit` is a large share of `Answers Written`, the 150-word cap
is shaping what people write, and that is worth knowing before anyone reads the
answers as freely given.

**Table** drilling from theme to answers: `People[Name]`,
`ResponseThemes[Theme]`, `Responses[ResponseText]`. Cross-filter from the theme
bar handles the drill — click a theme, the table filters.

Note the `Responses[ResponseText]` column here needs the **inactive**
`DimRole[RoleKey]` → `Responses[RoleKey]` relationship left inactive; the table
filters via `People`, which is the active path.

**On sentiment**: read the note at the foot of `queries/03-textanalysis.m`
before promising it. Short version — Power BI's built-in scoring needs
Premium/PPU and sends the text to Azure, which is an information-governance
question for OFFICIAL SENSITIVE free text about people's jobs. What is shipped
here needs neither and is auditable. With ~100 answers, reading them is feasible
and better; the dashboard's job is to say which to read first.

---

## 8. Before you publish

- **Refresh once more end to end** and watch for errors, not just warnings.
- **Page 6 first**, every time. Then page 1's `Total Posts` (should be 80) and
  `Total Colleagues` (~111).
- **Restrict the workspace.** This report contains every respondent's name,
  grade, area and free text. The app's `varIsAdmin` gate is a Power Fx variable,
  not security, and none of it travels to Power BI. Publish to a workspace whose
  membership is the HR admin group and check the members list yourself — do not
  assume the app's gating carries over. It does not.
- **The CSV and refresh in the Service**: Dataverse needs no gateway. A CSV on a
  local path does. If `CapacityPath` still points at your machine, scheduled
  refresh will fail in the Service with a gateway error — that is §1's decision
  coming back.
- **Row-level security** is *not* configured, deliberately: everyone who can open
  this report sees everything. If that is not acceptable, RLS on `People[Area]`
  is the obvious cut, and it is a conversation to have before publishing, not
  after.
