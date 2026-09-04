# Aurora Preference — Power BI dashboard

Build spec, data model, Power Query and DAX for the reporting layer over the
Aurora Role Preference app. Covers PAB-6119 (respondent table) and the
over/under-subscription, what-if and alignment reporting.

> **There is no `.pbix` in here, and I could not produce one.** It is a
> proprietary binary that only Power BI Desktop writes. What is here is
> everything that *goes into* one — the queries, the model, every measure, the
> cleaned capacity data and a page-by-page layout — so building it is assembly,
> not authoring. Realistically half a day.

---

## 1. Files

| File | What it is |
|---|---|
| `data/roles_capacity.csv` | The roles-available sheet, cleaned — the **second source**, post counts only |
| `queries/01-sources.m` | Power Query for every source table |
| `queries/02-whatif-assignment.m` | The capacitated random assignment |
| `queries/03-textanalysis.m` | Word frequency, theme tagging, and the sentiment options |
| `measures.dax` | Every measure, grouped by page |
| `BUILD.md` | The click-level Desktop assembly walkthrough — start there when building |

## 2. Build order

> **`BUILD.md` is the click-level version of this section** — parameters,
> paste order, every relationship setting, and each page's field wells. It
> also opens with three things in the current files that will stop the build.
> Read its §0 before you start.


1. Power BI Desktop → **Blank report**.
2. **Manage Parameters** → add `EnvUrl` (text, your Dataverse URL) and
   `WhatIfSeed` (whole number, `1`).
3. Put `roles_capacity.csv` somewhere stable and set `CapacityPath` to it.
   SharePoint, not a local path: a local path needs a gateway to refresh in the
   Service and only works from your machine. See §3.
4. Set `AppRoles` and `CapacityCsv` to **Disable Load** — they are staging for
   the merged `DimRole`, and loading them gives you three role tables.
5. Paste each query from `queries/` via **New Source → Blank Query → Advanced
   Editor**, one per block, named as its header says. Order matters:
   `01-sources` before `02` and `03`, since those read its outputs.
6. **Fix the table names.** The Dataverse connector lists tables by *logical*
   name (`cr123_rolepreferencepeople`), not the display names the app uses. Open
   the navigator once, note the real prefix, and substitute it throughout.
7. Build the relationships in §3.
8. Create a blank `_Measures` table and paste `measures.dax` into it.
9. Lay out the pages per §4, and **check page 6 before trusting anything else** —
   it is where a broken RoleKey join shows up.

## 3. Data model — two sources, one role dimension

**Dataverse is the app data. The CSV supplies post counts and nothing else.**
They meet on `RoleKey`, and that join is the fragile part of the whole model.

```
   DATAVERSE (live)                          CSV (post counts)
   ────────────────                          ─────────────────
   AppRoles ─────────┐                  ┌──── CapacityCsv
   People            │  FULL OUTER on   │
   Preferences       └──►  RoleKey  ◄───┘
   Responses                  │
   Alignments                 ▼
                         ┌─────────┐
                         │ DimRole │   RoleKey, RoleName, Posts,
                         └─────────┘   RoleFamily, JoinStatus
```

`AppRoles` and `CapacityCsv` are **staging queries — set both to Disable Load.**
Only the merged `DimRole` reaches the model, so there is one role table, one set
of relationships, and no "which role name do I use" question. Where both sides
have a name, the app's wins: it is what the person actually saw on screen.

`DimRole[JoinStatus]` is the payoff. Every role lands in exactly one bucket:

| JoinStatus | Meaning | Today |
|---|---|---|
| `Matched` | in both sources, has posts | the normal case |
| `Matched - but zero posts` | in both, 0 posts | R16 |
| `Capacity sheet only - no role key` | the `?` rows | 3 rows, 3 posts |
| `Capacity sheet only - missing from the app` | nobody could rank it | R08 was here |
| `App only - no post count` | rankable, but no capacity to allocate | check after refresh |

### Dataverse column names, and the three that lie

Every query renames the logical Dataverse columns to friendly model names, so
the report never shows `cr174_` anything. Model names match the Dataverse
**display** names one-for-one, so anyone who sees a field on a visual can go and
find it in the table — with one deliberate exception, noted below.

Three logical names do not describe what they hold. This is not sloppiness in
the app: Dataverse **freezes a logical name when a column is created** and never
changes it, however often the display name is edited afterwards. The tables were
built from §"Tables" of `docs/dataverse-setup.md`, which compresses several
columns into one schema row — `| EmployeeID / RoleKey | Text |` means *two*
columns, and `Grade` / `Area` / `Team` are three. Whoever built them created one
column per row, then added the missing ones separately and renamed the display
names to suit. The app patches by display name, so it works, and nothing
surfaces the mismatch until something reads the table over TDS — like this
report.

| Table | Logical name | Holds | Model name |
|---|---|---|---|
| Preferences | `cr174_employeeidrolekey` | **the employee id alone** (`60412`) | `EmployeeID` |
| PreferenceResponses | `cr174_employeeidrolekey` | **the employee id alone** | `EmployeeID` |
| People | `cr174_gradeareateam` | **the grade alone** (`SG6`) | `Grade` |

All three confirmed against the data — they are misnomers, not composites, and
must not be split. `RoleKey`, `Area` and `Team` exist as proper columns of their
own on those tables.

Two further names differ from what a reader might guess, and are used as
Dataverse spells them:

| Table | Logical name | Model name |
|---|---|---|
| Alignments | `cr174_assignedreason` | `AssignedReason` |
| Alignments | `cr174_rejectcomments` | `RejectComments` |
| Alignments | `cr174_decisionon` | `DecisionOn` |

**The one deliberate divergence:** `Roles.RoleName` becomes `AppRoleName`. The
capacity CSV also has a `RoleName` and `DimRole` merges the two, so distinct
names keep that merge readable. `DimRole` emits a single `RoleName` at the end.

Two value formats matter as much as the names, and both fail silently rather
than erroring:

- `Alignments[Decision]` is **`Accepted` / `Rejected`**, not `Accept` / `Reject`.
- `Active` and `IsAdmin` are Dataverse **Yes/No**, which arrive over TDS as a
  logical *or* as `0`/`1`. The queries coerce rather than declaring a type.

> If the Dataverse tables are ever rebuilt, fixing the compressed rows in
> `docs/dataverse-setup.md` first would stop this recurring. That file belongs
> to the app workstream, not this one.

### Star schema

```
                    ┌──────────────┐
                    │    People    │  EmployeeID (1)
                    └──────┬───────┘
        ┌──────────────────┼──────────────────┬─────────────────┐
        │ *                │ *                │ *               │ *
  ┌───────────┐     ┌────────────┐     ┌────────────┐   ┌──────────────────┐
  │Preferences│     │ Responses  │     │ Alignments │   │ WhatIfAssignment │
  └─────┬─────┘     └─────┬──────┘     └─────┬──────┘   └────────┬─────────┘
        │ *               │ *                │ *                 │ *
        └─────────────────┴──────────────────┴───────────────────┘
                                   │
                            ┌──────┴──────┐
                            │   DimRole   │  RoleKey (1)
                            └─────────────┘
```

| From | To | Cardinality | Active? |
|---|---|---|---|
| `People[EmployeeID]` | `Preferences[EmployeeID]` | 1→* | yes |
| `People[EmployeeID]` | `Responses[EmployeeID]` | 1→* | yes |
| `People[EmployeeID]` | `Alignments[EmployeeID]` | 1→* | yes |
| `People[EmployeeID]` | `WhatIfAssignment[EmployeeID]` | 1→* | yes |
| `People[EmployeeID]` | `RejectReasonsUnpivoted[EmployeeID]` | 1→* | yes |
| `People[EmployeeID]` | `PreferenceWide[EmployeeID]` | 1→* | yes |
| `DimRole[RoleKey]` | `Preferences[RoleKey]` | 1→* | yes |
| `DimRole[RoleKey]` | `Responses[RoleKey]` | 1→* | **no** |
| `DimRole[RoleKey]` | `Alignments[AssignedRoleKey]` | 1→* | **no** |
| `DimRole[RoleKey]` | `WhatIfAssignment[AssignedRoleKey]` | 1→* | **no** |
| `ResponseThemes[EmployeeID]` | `People[EmployeeID]` | *→1 | yes |
| `DimRole[RoleKey]` | `WhatIfRoleFill[RoleKey]` | 1→* | yes |

`WordFrequency` and `WhatIfSeedValue` get **no relationships**. The first is
pre-aggregated to one row per word and has no `EmployeeID` to join on, so it
cannot be cross-filtered — do not put a slicer beside the word cloud and expect
it to respond. The second is a one-row lookup carrying `WhatIfSeed` into the
model, because DAX cannot read a Power Query parameter.

Power BI allows only one active path between two tables. Keep the `Preferences`
one active — that is what the demand analysis needs — and reach the others with
`USERELATIONSHIP` inside a measure.

### Refresh: the CSV is the awkward half

Dataverse refreshes in the Power BI Service with no gateway. A CSV on a local
path does not — it needs an **on-premises data gateway**, and it only ever works
from your machine. Put the file in the same SharePoint site the team already
uses and both problems disappear, along with "only one person can update the
post counts".

If the two-source split becomes annoying, the alternative is to add a `Posts`
whole-number column to the `RolePreference Roles` table in Dataverse and drop
the CSV entirely: one source, no gateway, no drift, and the app itself could
show remaining capacity later. That is a bigger change than it looks — the post
counts would then need maintaining in Dataverse rather than in Excel, which may
not suit whoever owns them — so it is worth a conversation, not a unilateral
switch.

## 4. Pages

### Page 1 — Preference process summary

Cards across the top: `Total Colleagues`, `Total Areas`, `Total Teams`,
`Total Line Managers`, `Total Roles Available`, `Total Posts`, `Completion Rate`,
`People Per Post`.

Then:
- **Stacked column, Role distribution by area** — axis `People[Area]`, legend
  `DimRole[RoleFamily]`, value `Applications`. Family rather than individual
  role, or the legend has 66 entries.
- **Donut, where people are in the process** — a small calculated column on
  People (`Not started` / `In progress` / `Completed`) against `Total Colleagues`.
- **Slicers**: Area, Grade, Team.

> The wireframe shows a 100% completion card. Point it at `Completion Rate`
> rather than hard-coding it; at the time of writing the app reported 1 of 111.

### Page 2 — Respondent table (PAB-6119)

One table, one page, filterable. Columns: Name, EmployeeID, Grade, Area, Team,
Preference 1/2/3 (from `PreferenceWide`, joined to `DimRole` for names),
Submitted date, Stage 2 status, and — once Phase 2 data exists — Assigned role
and Decision.

Slicers down the side: Area, Grade, Team, Stage 2 status, and a search box
(Text filter or the Text Slicer visual) on Name.

Turn on **Data > Export data** for this page — the practical ask behind PAB-6119
is usually "can I get this into Excel".

### Page 3 — Over and undersubscribed roles

The wireframe's heatmap is role × area. That works, but the more decision-useful
cut is **role × preference rank**, because it separates "lots of people want this
most" from "lots of people listed it third".

- **Matrix** — rows `DimRole[RoleName]`, columns `Preferences[Rank]`,
  values `Applications`, plus `Posts For Role` and `Subscription Ratio` as
  columns. Conditional formatting: background colour on `Subscription Ratio`,
  diverging, centred on 1.0 — white at exactly filled, red above, blue below.
- **Cards**: `Roles Oversubscribed`, `Roles With No Interest`,
  `Roles With Zero Posts`, `Roles Not Reconciled`.
- **Bar chart, most contested** — `DimRole[RoleName]` by `Oversubscription`,
  top 10 descending.
- Keep the role × area heatmap as a second visual if Kate wants it; use
  `People[Area]` on columns and the same conditional formatting.

Put `Roles Not Reconciled` on the page, not in a tooltip, linked through to
page 6. A heatmap that quietly drops three roles because they have no key is
worse than one that says so.

### Page 4 — What if everyone got their first choice

- **Cards**: `Pct Got 1st Choice`, `Pct Got 2nd Choice`, `Pct Got 3rd Choice`,
  `Pct Unassigned`, `Posts Unfilled`.
- **The big table** — the wireframe's layout, straight off `WhatIfAssignment`:
  Name, Preference 1, Preference 2, Preference 3, Assigned. Conditional-format
  the Assigned column on `OutcomeRank` so 1st/2nd/3rd/unassigned read at a glance.
- **Funnel or stacked bar** of the four outcomes.
- **Bar, roles left unfilled** — from `WhatIfRoleFill`, `PostsUnfilled` descending.
- **A text box carrying `What If Caveat`.** Not optional. One run is one shuffle;
  whoever reads this page needs to know the individual rows are not decisions.

Re-run at three or four different `WhatIfSeed` values and note whether the
headline percentage moves. If it swings widely, say so — that instability is
itself the finding.

### Page 5 — Alignment: accepted and challenged

- **Cards**: `Alignments Published`, `Decisions Made`, `Awaiting Decision`,
  `Acceptance Rate`, `Challenge Rate`.
- **Bar, why people challenged** — `RejectReasonsUnpivoted[Reason]` by
  `Reason Mentions`, with `Pct Of Challenges Citing Reason` as a tooltip.
  Multi-select, so the percentages sum past 100 by design; `Reasons Per
  Challenge` gives the average.
- **Card: `Aligned Outside Top 3`** — people given a role they did not rank. The
  number most likely to predict a challenge.
- **Table** of challenges: Name, Area, Assigned role, Reasons, free text.

### Page 6 — Source reconciliation

The page nobody asks for and everybody needs, because a two-source model fails
quietly: a role that drops out of the join disappears from the heatmap with no
error and the totals stop adding up without saying so.

- **Table** on `RoleReconciliation`: RoleKey, RoleName, Posts, JoinStatus.
- **Cards**: `Roles Missing A Key`, `Roles Missing From The App`,
  `Roles Missing A Post Count`, `Preferences For Unknown Role`.
- Check it after every refresh, and especially after anyone edits either source.

### Page 7 — Themes in the free text

- **Word cloud** — the *Word Cloud* visual from AppSource, `WordFrequency[Word]`
  by `WordFrequency[People]`. Weight by people, not raw frequency: one person
  writing "flood" eleven times should not outrank eleven people writing it once.
- **Bar, themes** — `ResponseThemes[Theme]` by `Pct Mentioning Theme`.
- **Cards**: `Answers Written`, `Median Answer Length`, `Answers At The Limit` —
  if many answers sit at 145+ words, the 150-word cap is shaping what people say
  and that is worth knowing.
- **Table** drilling from a theme to the answers behind it.

On sentiment specifically, read the note at the foot of `queries/03-textanalysis.m`
before promising it. Short version: Power BI's built-in sentiment needs Premium
or PPU and sends the text to Azure, which is a data-protection question for
OFFICIAL SENSITIVE free text about people's jobs; the theme tagging shipped here
needs neither and is auditable. With ~100 answers, reading them is feasible and
better — the dashboard's job is to say which to read first.

---

## 5. What the capacity sheet says, and four problems in it

`Preference_Process_roles_available.xlsx`: **66 roles, 80 posts.**

Against ~111 people on the People table, that is **roughly 1.4 people per post**
before anyone's preferences are considered. The what-if page exists to turn that
into a number Kate can act on, but the headline is already visible: this is
oversubscribed in aggregate, and some people will not get any of their three.

Four things need a human decision before the numbers are trustworthy:

1. **Three roles have `?` instead of a role key** — the Officer PPD North West
   DMO post, the Team Leader PMO Portfolio Reporting (Governance) post, and the
   Team Leader RMA Anglian RFCCs post. Three posts that cannot be joined to
   anything anyone ranked. They are kept in the CSV so the post total stays
   right, and flagged in `DataIssue`.

2. **R16 has zero posts** — Local Operations FCRM Advisor Local Levy North East.
   If it is still offered in the app, someone can rank it and can never be given
   it. Either give it a post or withdraw it from the app.

3. **R08 is in this sheet but was missing from the app's Roles table.** That is
   the `[missing role: R08]` a tester reported. The sheet says it is "Advisor -
   Portfolio Management Office - Portfolio Reporting & Insights - Benefits,
   Outcomes & Performance", 1 post. Adding that row to Dataverse fixes it, and
   because Preferences stores the key rather than the name, it resolves already
   submitted rankings with no resubmission.

4. **Two annotations contradict the per-row counts.** R32 is marked "4 roles
   available in total" while rows R32–R36 plus the unkeyed Officer PPD row each
   say 1 post (6 in total); R40 says "3 roles available in total" while R40–R44
   each say 1 (5 in total). Either the annotations are stale or the per-row
   numbers are. **The model uses the per-row `No Posts` column**, so if the
   annotations are right, `Total Posts` is overstated by 4. Worth 30 seconds with
   whoever wrote the sheet.

Also: keys run R01–R65 with **R57 and R58 absent**, and there are no duplicates.
The gap is probably just unused numbering, but confirm it is not two dropped rows.

---

## 6. Refresh and access

- **Storage mode**: **Import**. Not a preference — `DimRole` is a merge across
  two sources, the what-if is a `List.Accumulate` fold and the text analysis
  expands list columns, none of which DirectQuery can do. `BUILD.md` §3 has the
  full reasoning, including why "DirectQuery stores nothing" is not an
  information-governance answer here.
- **Refresh**: Dataverse via the connector needs no gateway. The capacity CSV
  does if it stays on a local path — put it on SharePoint and that goes away.
- **Row-level security**: the app's admin gate is `varIsAdmin` in Power Fx, which
  is not security and does not travel to Power BI. This report contains every
  respondent's name, grade, area and free text. Restrict the workspace to the HR
  admin group, and do not publish it to a wider audience on the assumption that
  the app's gating carries over. It does not.
- The privacy notice on the app's landing page tells people their data is used
  for the Aurora programme and held for up to two years. A published dashboard is
  within that, but sending the free text to Azure for sentiment scoring is a
  separate question — see §4 page 6.
