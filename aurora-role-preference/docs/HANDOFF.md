# Aurora — Role Preference: handoff

Everything a new session needs to continue this build. Written to be read
top-to-bottom once, then used as reference.

**Branch:** `claude/power-apps-canvas-yaml-dbqoyt` → open PR
[#9](https://github.com/Abimbola98/Abimbola98/pull/9) against `main`.
**App root:** `aurora-role-preference/`.

---

## 1. What this is

A Microsoft Power Apps **canvas app** for the Environment Agency's Aurora Change
Transformation programme. Staff rank the roles they are eligible for, then answer
two standard questions about each of their **top three** choices. HR admins track
who has completed it and read the submissions. Once the outcome is decided, each
person is shown the role they have been aligned to and the reasoning behind it,
and either accepts it or says why not.

The app is authored as **`.pa.yaml` source in Git** and moved into Power Apps
Studio by **pasting one screen at a time through Code View**. There is no
`pac canvas pack` step in the current loop and no `.msapp` in the repo.

### The flow

| Stage | Screen | What happens |
|---|---|---|
| — | `scrLanding` | Identity, welcome panel, action cards, GDPR notice |
| 1 | `scrForm` | Rank every eligible role (dropdown per row, duplicate-rank validation) |
| 1 | `scrReview` | Check the ranking; "Change ranking" (warns first); continue to Stage 2 |
| 2 | `scrQuestions` | Two questions × top three roles, 150 words each |
| — | `scrCompleted` | Read-only results, locked |
| admin | `scrOverview` | All-staff completion tracker, tabs, counters |
| admin | `scrSubmissions` | Submissions table, per-person answers, Delete |
| 3 | `scrAlignment` | The role they have been aligned to + the reasoning; Accept / Reject |
| 3 | `scrRejection` | Rejection reasons (tick boxes) + 150 words; Save draft / Submit |
| 3 | `scrAlignLocked` | Read-only outcome, locked |

`scrDetail` exists in the repo but is **orphaned** — nothing navigates to it since
role-description pages were dropped. It does not need to exist in Studio.

**Stage 1 does not lock.** The ranking is a draft (`Stage1Status = "Draft"`) and
stays editable until the whole form is submitted at Stage 2. Only
`btnConfirmSubmit` makes anything final.

**Stage 3 (role alignment) is Phase 2, and is built.** It is a separate loop
that opens only once Kate/Claire publish an alignment for a person: it does not
touch Stage 1 or 2 data, it writes to its own table, and it has its own lock.
See §10.

---

## 2. Repo map

```
aurora-role-preference/
├── Src/                       # SOURCE OF TRUTH — edit these
│   ├── App.pa.yaml            # offline/demo seed collections (not the live OnStart)
│   ├── scrLanding.pa.yaml     scrForm.pa.yaml     scrReview.pa.yaml
│   ├── scrQuestions.pa.yaml   scrCompleted.pa.yaml
│   ├── scrOverview.pa.yaml    scrSubmissions.pa.yaml
│   ├── scrAlignment.pa.yaml   scrRejection.pa.yaml    # Phase 2
│   ├── scrAlignLocked.pa.yaml                         # Phase 2
│   └── scrDetail.pa.yaml      # orphaned
├── paste/                     # GENERATED + hand-written formula files
│   ├── scr*.controls.yaml     # generated — never edit by hand
│   ├── App_OnStart.dataverse.powerfx     # the LIVE OnStart
│   ├── App_OnStart.powerfx               # offline/demo OnStart
│   ├── App_OnStart.alignments-stub.powerfx  # section 4b without the table
│   ├── scrOverview_OnVisible.powerfx
│   ├── scrSubmissions_OnVisible.powerfx
│   ├── Phase3-5-button-formulas.powerfx  # the four Dataverse write formulas
│   ├── Phase2-alignment-formulas.powerfx # the three alignment writes (reference)
│   ├── seed-alignments-dummy.powerfx     # dummy alignments for testing
│   ├── export-alignment-columns.powerfx  # the PAB-6118 export collection
│   ├── diagnose-missing-roles.powerfx    # read-only diagnostics
│   ├── one-off-purge-withdrawn.powerfx   # destructive, opt-in
│   ├── one-off-relabel-eligibilities.powerfx
│   └── HOW-TO-PASTE.md        # the operational guide — keep it current
├── tools/
│   ├── gen_paste.py           # Src/*.pa.yaml -> paste/*.controls.yaml
│   └── scan_paste.py          # pre-push hazard scanner
├── export/
│   └── PAB-6118_Aurora_Export_Template.xlsx   # the 20-column sheet for Kate/Claire
├── docs/
│   ├── dataverse-setup.md     # 7-phase connection guide + table schemas
│   ├── PAB-6118-export.md     # the export/import loop for the alignment data
│   ├── hover-pressed-cheatsheet.md
│   ├── HANDOFF.md             # this file
│   └── Aurora_..._Application_Architecture_Document.docx
└── README.md
```

**Deliberately not committed:** the seed spreadsheets
(`RolePreference_Roles_seed.xlsx`, `RolePreference_Eligibilities_seed.xlsx`) —
they contain OFFICIAL SENSITIVE names. They were generated and sent to the user
as files only. Nothing in the repo depends on them.

---

## 3. The build loop

```bash
cd aurora-role-preference
#  1. edit Src/<screen>.pa.yaml
python3 tools/gen_paste.py            # or: gen_paste.py scrForm  for one screen
python3 tools/scan_paste.py           # MUST be clean before committing
git add -A && git commit && git push -u origin claude/power-apps-canvas-yaml-dbqoyt
#  then: user re-pastes the changed screens in Studio
```

`scan_paste.py` returning `PROBLEMS: 0` is as close as this project gets to a
test suite. There is nothing to unit-test — "correct" means *Studio accepts the
paste and the screen renders without clipping*. Every rule in the scanner
encodes a failure that actually happened.

**Do not edit `paste/*.controls.yaml` by hand.** They are regenerated wholesale
and your edit will be silently reverted on the next run.

---

## 4. The Power Apps YAML format — in depth

This is the part that took the most trial and error. Read it before touching a
`.pa.yaml`.

### 4.1 Two dialects of the same tree

**`Src/*.pa.yaml`** is the pack/unpack format: a `Screens:` mapping, one screen
key, its `Properties:`, then `Children:`.

```yaml
Screens:
  scrForm:
    Properties:
      Fill: =ColorValue("#F2F5F7")
      OnVisible: =If(varStage2Submitted, Navigate(scrCompleted))
    Children:
      - conRoot:
          Control: GroupContainer@1.5.0
          Variant: AutoLayout
          Properties:
            Width: =Parent.Width
          Children:
            - conHeaderBar:
                Control: GroupContainer@1.5.0
                ...
      - conContinueOverlay:      # sibling of conRoot — overlays live here
          Control: GroupContainer@1.5.0
          Variant: ManualLayout
          ...
```

**`paste/*.controls.yaml`** is what the clipboard needs: a **top-level list of
controls**, no `Screens:`, no screen node, dedented 6 spaces.

```yaml
- conRoot:
    Control: GroupContainer@1.5.0
    Variant: AutoLayout
    Properties:
      Width: =Parent.Width
    Children:
      - conHeaderBar:
          ...
- conContinueOverlay:
    ...
```

Pasting the `Src` form onto a screen node fails. `tools/gen_paste.py` does the
conversion: drop everything through the screen's `    Children:` line, dedent 6,
strip comments and blank lines.

### 4.2 Control node grammar

```yaml
- <ControlName>:                 # unique across the WHOLE APP (see 4.7)
    Control: <Type>@<x.y.z>      # version-pinned, exact
    Variant: <VariantName>       # containers + galleries only
    Properties:
      <PropertyName>: =<PowerFx>         # single line
      <PropertyName>: |-                 # multi-line block scalar
        =<PowerFx>
        <continuation>
    Children:
      - <ChildName>:
          ...
```

Every property value begins with `=`. The `|-` block scalar is the multi-line
form and carries strict extra rules — see 4.6.

**Variants in use:**

| Control | Variant | Meaning |
|---|---|---|
| `GroupContainer@1.5.0` | `AutoLayout` | flex container; children flow by `LayoutDirection` |
| `GroupContainer@1.5.0` | `ManualLayout` | absolute positioning; children use `X`/`Y` |
| `Gallery@2.15.0` | `Vertical` | the only gallery variant used |

### 4.3 The five pinned control IDs

Studio **silently drops** any control whose type id it does not recognise — no
error, the control just is not there. That produced an empty container in early
rounds. Only these five are used, and the version suffix must match this
environment exactly:

| Control id | Used for | Count |
|---|---|---|
| `Label@2.5.1` | all text; **every button** (Label + `OnSelect`); overlay scrims; the rejection **tick boxes** | 331 |
| `GroupContainer@1.5.0` | every layout box, card, pill background, strip, overlay | 214 |
| `Gallery@2.15.0` | role list, rankings, admin tables, bullet lists, rejection reasons | 9 |
| `Classic/TextInput@2.3.2` | the six Stage-2 answer boxes + the rejection comments box | 7 |
| `Classic/DropDown@2.3.1` | the rank picker on `scrForm` | 1 |

There is **no Checkbox**, which is why the rejection reasons on `scrRejection`
are Labels: the box Label shows a tick when `ThisItem.Chosen`, and both it and
the reason text flip it with `Patch(colRejectReasons, ThisItem, …)`. Pinning a
sixth control id for one screen is not worth risking a failed paste.

There are **no Button, Rectangle, Icon or Timer controls**. Buttons are Labels
with `OnSelect`, which is why `Label@2.5.1`'s property set matters so much.

If Power Apps bumps a version, drop a fresh control on a scratch screen →
right-click → **View code** → copy the exact `Control:` id → re-stamp, and update
`OK_CONTROLS` in `tools/scan_paste.py`.

### 4.4 Validated property sets

These are the properties actually in use and confirmed to survive paste. Treat
anything outside these lists as unverified — a wrong property is `PA2108 Unknown
property 'X' for control type 'Y'` and fails the **whole** paste.

**`GroupContainer@1.5.0`** — `BorderColor`, `BorderStyle`, `BorderThickness`,
`DropShadow`, `Fill`, `FillPortions`, `Height`, `LayoutAlignItems`,
`LayoutDirection`, `LayoutGap`, `LayoutJustifyContent`, `LayoutMinHeight`,
`LayoutMinWidth`, `LayoutOverflowY`, `LayoutOverflowX`, `PaddingTop/Bottom/Left/Right`,
`RadiusTopLeft/TopRight/BottomLeft/BottomRight`, `Visible`, `Width`, `X`, `Y`.

> No `LayoutMode` — the `AutoLayout`/`ManualLayout` variant already sets it, and
> passing it fails the paste.

**`Label@2.5.1`** — `Align`, `AutoHeight`, `BorderColor`, `BorderStyle`,
`BorderThickness`, `Color`, `DisplayMode`, `Fill`, `FillPortions`, `FontWeight`,
`Height`, `HoverFill`, `OnSelect`, `PaddingTop/Bottom/Left/Right`, `PressedFill`,
`Size`, `Text`, `VerticalAlign`, `Visible`, `Width`, `X`, `Y`.

> **No `Radius*`** — so pills and badges render square unless wrapped in a
> container. **No `AutoWidth`.**
>
> **`HoverFill` and `PressedFill` DO survive paste** — this was got wrong once,
> corrected by the user with a real View-code sample, and both are now baked into
> all buttons. There is **no** serialisable `HoverColor`, `PressedColor`,
> `HoverBorderColor` or `PressedBorderColor` on the modern Label, so button text
> and border colour stay constant on hover; the fill change is the whole signal.

**`Gallery@2.15.0`** — `FillPortions`, `Height`, `Items`, `TemplateFill`,
`TemplatePadding`, `TemplateSize`, `Width`.

> **Rejects `Padding*` and `LayoutDirection`** (`PA2108`). Put the inset on a
> container inside the template instead.

**`Classic/TextInput@2.3.2`** — `BorderColor`, `BorderThickness`, `Color`,
`Default`, `Fill`, `FillPortions`, `Height`, `HintText`, `MaxLength`, `Mode`,
`OnChange`, `Radius*` (unlike Label), `Size`, `Width`.

**`Classic/DropDown@2.3.1`** — `BorderColor`, `BorderThickness`, `Color`,
`Default`, `Fill`, `FillPortions`, `Height`, `Items`, `OnChange`, `Width`.

### 4.5 The layout model — the single most important section

**Auto-layout containers do not grow to fit their contents.** A container with no
`Height` and no `FillPortions` balloons to an arbitrary default; one with
`FillPortions: =1` shrinks to whatever the parent has left, which can be nothing.
Both failure modes shipped and had to be fixed. The rule that finally worked:

> **Every container's `Height` is either a literal sum of its children, or a
> formula over their `.Height` properties.**

```yaml
# text that wraps -> AutoHeight label, parent sums it
- cardPrivacy:
    Properties:
      FillPortions: =0
      Height: =lblPrivacyBody.Height + lblPrivacyLink.Height + 74
- qsnBlk1a:
    Properties:
      Height: =qsnQ1a.Height + 176 + If(qsnErr1a.Visible, 32, 0)
- cardAnswers:
    Properties:
      Height: |-
        =72 + cmpSec1.Height
            + If(CountRows(colLockedRanking) >= 2, cmpSec2.Height, 0)
            + If(CountRows(colLockedRanking) >= 3, cmpSec3.Height, 0)
```

A parent referring to a child's `.Height` while the child's `Width` refers to
`Parent.Width` is **not** circular — different properties, and Power Apps
resolves it. This is the workhorse pattern; there are ~30 of them.

Note the conditional sums: an invisible child is excluded from auto-layout, but
its `.Height` still returns a value, so a hidden section must be multiplied out
of the total or the card grows phantom whitespace.

**Sizing cheat sheet**

- `FillPortions: =0` — keep my own height (vertical parent) or width
  (horizontal parent). **The default for almost everything.**
- `FillPortions: =1` — take the remaining space. At most one per axis per
  container, and only where the leftover is genuinely large.
- A width-less label in a vertical parent needs `Width: =Parent.Width`; in a
  horizontal parent it needs `FillPortions: =1`.
- `LayoutMinHeight` gives a flexible region a floor (used on the admin tables:
  `LayoutMinHeight: =154 + 5 * 44`).

**Scrolling — exactly one surface per screen.** Only `conContent` carries
`LayoutOverflowY: =LayoutOverflow.Scroll`. `conRoot` does not, on any screen, and
galleries are sized so they never scroll internally except where a list is
genuinely unbounded (the two admin tables). Two nested scroll regions plus a
gallery is what produced "this screen has three scroll bars".

**Galleries clip their last row even when the arithmetic looks exact.** The
default `TemplatePadding` adds unmetered space between items, so
`Height: =N * TemplateSize` always falls short. Every full-list gallery sets
`TemplatePadding: =0` **and** adds slack:

```yaml
- galRoles:
    Properties:
      Items: =colRanks
      Height: =CountRows(colRanks) * 88 + 16
      TemplateSize: =88
      TemplatePadding: =0
```

**Galleries cannot hold variable-height content at all.** `TemplateSize` is a
fixed number, so a question that wrapped an extra line or a 150-word answer ran
past its row — clipped text *and* an unwanted inner scrollbar. Where the item
count is known and small (3 sections × 2 questions), the sections are laid out as
**explicit controls** instead: `qsnSec1..3` on `scrQuestions`, `cmpSec1..3` on
`scrCompleted`, `subSec1..3` on `scrSubmissions`. That is why those files are
long and repetitive. It is deliberate — do not "simplify" them back into a
gallery.

**The landing header bug worth remembering:** its three columns were
`Parent.Width * 0.5`, `* 0.7` and `* 0.20` — 1.4× the bar. It clipped at 100%
browser zoom and looked fine at 75%, because zooming out gives the bar more CSS
pixels. Proportional widths that do not sum to 1 are a latent bug of this shape.

### 4.6 Embedding Power Fx — block-scalar rules

Multi-line formulas use `|-`. Inside a block scalar, the deserializer re-scans
the text as YAML, which creates two hard rules:

1. **No line may start with `Name: value`.** It is read as a YAML mapping →
   `PA1001 YamlInvalidSyntax; While scanning a multiline plain scalar, found
   invalid mapping`. This bites record literals *and* prose in `/* */` comments
   — a comment line beginning `lose them: rows are rebuilt…` triggered it.
2. **Record literals stay on ONE line.** Never a bare `{` or `}` on its own line.

```yaml
# WRONG - fails the paste
OnSelect: |-
  =ClearCollect(colAnswers,
      {
          RoleKey: r1.RoleKey,
          QIndex: 0
      }
  )

# RIGHT - one record per line, continuations start with a symbol
OnSelect: |-
  =ClearCollect(
      colAnswers,
      {RoleKey: r1.RoleKey, RoleName: r1.RoleName, QIndex: 0, Answer: ""},
      {RoleKey: r1.RoleKey, RoleName: r1.RoleName, QIndex: 1, Answer: ""}
  )
```

Long strings are split across lines with `&` continuations, which begin with a
symbol and so are safe:

```yaml
Text: |-
  ="By using this app, you agree to us holding any personal information… "
  & "Data entered by you in this App will be collected… "
  & "Under the General Data Protection Regulation (GDPR)… "
```

**A single-line value containing `: ` must become a block scalar** — same error.
`Text: ="Completed: " & varCountDone` fails; the `|-` form works.

**Consequence for buttons:** a long behaviour formula full of record literals
**cannot live in pasted YAML at all**. That is why the four Dataverse writes are
in `paste/Phase3-5-button-formulas.powerfx` and pasted into the formula bar by
hand, and why the admin `↻ Refresh data` buttons ship unwired with a `Notify`
placeholder telling the maker to paste the OnVisible text into `OnSelect`.

### 4.7 Control naming

Control names are **global to the app**, and Studio silently renames a pasted
control that clashes with an existing one (`lblFoo` → `lblFoo_1`). Harmless for
most controls — formulas use `Parent`, `Self`, `ThisItem`, variables and
collections — **but fatal for the height-sum pattern**, which points a parent at
a named child.

So: any control referenced by name in a formula must have an app-unique name.
The convention is a screen prefix — `qsn*` (questions), `cmp*` (completed),
`sub*` (submissions). `scan_paste.py` rule 8 enforces this on every run.

It also means **paste each screen onto an empty screen node**. Pasting over
existing controls triggers the renames.

### 4.8 The complete paste-hazard catalogue

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | control missing, no error | unversioned/unknown `Control:` id | pin `@x.y.z` from View code |
| 2 | `PA1001 YamlInvalidSyntax` | `#` comment or blank line in the paste | generator strips both |
| 3 | `PA1001 … found invalid mapping` | block-scalar line starts `Name: value` | reword / restructure |
| 4 | `PA1001 … found invalid mapping` | bare `{` or `}` in a block scalar | one record per line |
| 5 | `PA1001 … found invalid mapping` | `: ` inside a single-line `=` value | use `|-` |
| 6 | `PA1001 Duplicate name 'X'` | property key twice in one `Properties:` | dedupe |
| 7 | `PA2108 Unknown property` | e.g. `Padding*` on a Gallery, `Radius*` on a Label | see 4.4 |
| 8 | height formula points at the wrong control | name collided, Studio renamed it | app-unique names |
| 9 | last gallery row cut off | `TemplatePadding` unaccounted | `TemplatePadding: =0` + slack |
| 10 | container balloons / collapses | no `Height` and no `FillPortions` | sum the children |
| 11 | `varX isn't recognized` on controls that never changed | OnStart references a data source that has not been added; the whole rule fails to bind and **every** variable it sets goes undefined | add the table, or swap the offending block for a literal stub — see §10 |

---

## 5. Screen inventory

Structure is uniform: `conRoot` (vertical, `Height: =Parent.Height`, **no**
scroll) → `conHeaderBar` (64) + `recGreenStrip` (4) + `conMain` (`FillPortions: =1`,
padding) → `conContent` (`Width: =Min(Parent.Width - 48, 1120)`, `LayoutGap`,
**the** scroll region). Overlays are **siblings of `conRoot`**, `ManualLayout`,
full-bleed, gated on a context variable.

| Screen | Key children | Overlay |
|---|---|---|
| `scrLanding` | `cardWelcome` (grid sizes to the tallest of Grade/Area/Team), `conActions` (`cardForm` + `cardAdmin`), `cardPrivacy` | — |
| `scrForm` | `cardDetails`, `calloutInstruction`, `panelErrors`, `cardRoles` → `galRoles` (`colRanks`, 88px rows, `drpRank`), `conFooter`, `lblHelpContact` | `conContinueOverlay` / `locShowContinue` |
| `scrReview` | `cardRanking` → `galRanking`, `btnChangeRanking`, `cardNext` | `conChangeOverlay` / `locShowChange` |
| `scrQuestions` | `conTopNav`, `qsnSec1..3` each = `qsnHdr{n}` + `qsnBlk{n}a` + `qsnBlk{n}b`; each block = `qsnQ` label + `qsnTxt` input + `qsnWc` counter + `qsnErr` red banner | `conSubmitOverlay` / `locShowSubmit` |
| `scrCompleted` | `cardSuccess`, `cardRanking` → `galRanking`, `cardAnswers` → `cmpSec1..3`, `cardNote` | — |
| `scrOverview` | `conTitleRow` (+ `conAdminRow` with `btnRefreshOverview`), `cardAllStaff` (`FillPortions: =1`, `LayoutMinHeight: =154 + 5 * 44`) → header + tabs + col-head + `galAllStaff`, `btnOpenSubmissions` | — |
| `scrSubmissions` | `conTopNav` (+ `btnRefreshSubs`), `cardTable` → `conColHdr` + `galRows` (96px), `panelExpand` → `subSec1..3` | `conDeleteOverlay` / `locShowDelete` |
| `scrAlignment` | `cardAliPrefs` → `aliSec1..3` each = `aliRow{n}` + `aliPanel{n}`; `cardAliRole` → `conAliRoleBody`; `cardAliDecide` → `btnAcceptRole` + `btnRejectRole` | `conAcceptOverlay` / `locShowAccept` |
| `scrRejection` | `cardRejRole`, `cardRejReasons` → `galRejReasons` (64px tick-box rows), `cardRejText` → `rejTxt` + `rejWc` + `rejErr`, `conRejFooter` | `conRejectOverlay` / `locShowReject` |
| `scrAlignLocked` | `cardLokBanner`, `cardLokRole`, `cardLokReject` → `conLokRejBody`, `cardLokNote` | — |

Every screen except `scrLanding` has **`← Back to home` top-left**; the old
bottom Home buttons were removed.

---

## 6. Data model

Five Dataverse tables, all prefixed `RolePreference ` — the space means every
reference must be single-quoted: `'RolePreference Roles'`.

| Table | Key columns |
|---|---|
| `RolePreference Roles` | `RoleName` (primary), `RoleKey`, `ShortDescription`, `Purpose`, `Responsibilities`, `Requirements`, `GradeContext`, `Active` (Y/N), `DefaultOption` (Y/N) |
| `RolePreference People` | `Name` (primary), `EmployeeID`, `Email` (lower-case UPN — the sign-in key), `Grade`, `Area`, `Team`, `IsAdmin` (Y/N) |
| `RolePreference Eligibilities` | `Name` (**Autonumber**, read-only), `EmployeeID`, `RoleKey` |
| `RolePreference Preferences` | `Name` (Autonumber), `EmployeeID`, `RoleKey`, `Rank` (whole no.), `SubmittedBy`, `SubmittedOn` (datetime), `Stage1Status` (`Draft`/`Submitted`) |
| `RolePreference PreferenceResponses` | `Name` (Autonumber), `EmployeeID`, `RoleKey`, `QIndex` (0/1), `QuestionText`, `ResponseText`, `SubmittedOn`, `Stage2Status` (`Draft`/`Submitted`) |
| `RolePreference Alignments` **(Phase 2)** | `Name` (Autonumber), `EmployeeID`, `AssignedRoleName`, `AssignedRoleKey`, `AssignedReason` (4000), `Decision` (`Accepted`/`Rejected`), `RejectReasons` (4000, `;`-separated), `RejectComments` (4000), `Status` (`Draft`/`Submitted`), `DecisionOn`, `DecisionBy` |

Full schema and the 7-phase connection guide: `docs/dataverse-setup.md`.

**`ResponseText` must be raised to 4000 characters.** The inputs carry
`MaxLength: =4000` so 150 words of anything fits; if the column stays at 2000,
`Patch` fails with *Length must be between 0 and 2000*. The same applies to
`AssignedReason`, `RejectReasons` and `RejectComments` on Alignments.

**Alignments has no unique constraint**, so nothing stops a second row for the
same `EmployeeID`. Every read is a `LookUp`, which takes the first — the import
in `docs/PAB-6118-export.md` is the place to enforce one row per person.

**Joins are by text key, not by relationship.** There are no Lookup columns —
`EmployeeID` and `RoleKey` are plain Text everywhere, matched with `=`. Converting
to real Lookups/Choices is a deliberate later hardening step; it would change
every formula.

**"Invalid argument type" in OnStart = a column type mismatch.** Power Fx
type-checks statically, so it fires even against empty tables.

### State inventory

**Collections** — `colRoles`, `colRanks`, `colLockedRanking`, `colAnswers`,
`colPrevAns`, `colFormErrors`, `colAllStaff`, `colOverviewRows`,
`colSampleAnswers` (stub), `colPreferences` (legacy), `colRoleQuestions` (unused —
Workstream 7 standardised the questions), and for Phase 2
`colRejectReasonList` (the master list — **replace the three placeholders with
Claire's final wording and nothing else changes**) and `colRejectReasons`
(`{Idx, Reason, Chosen}`, the working copy with any saved draft ticked back on).

**Globals** — `varUser` (record: Name/EmpId/Grade/Area/Team/LastLogin),
`varUserEmail`, `varIsAdmin`, `varStage1Submitted`, `varStage1Date`,
`varStage2Submitted`, `varStage2Date`, `varDraftSaved`, `varSelectedOverviewId`,
`varStaffTab`, `varCountAll`, `varCountDone`, `varCountOutstanding`,
`varAdminRefreshedAt`, `varQ1a`–`varQ2b` (question-text fragments),
`varDetailRoleKey`, `varDetailOrigin` (both orphaned with `scrDetail`); and for
Phase 2 `varAlign` (the record read from Alignments), plus the flat globals the
screens actually read — `varAlignRole`, `varAlignReason`, `varAlignDecision`,
`varAlignReasonsText`, `varAlignComments`, `varAlignStatus`, `varAlignDate`,
`varAlignPublished`, `varAlignSubmitted`, `varAlignDraftSaved`. They are flat
rather than reads off `varAlign` so the confirm buttons can update the screens
straight after a write, without rebuilding the whole record.

**Context vars** — `locShowContinue`, `locShowSubmit`, `locShowChange`,
`locShowDelete`, `locDelId`, `locDelName`; Phase 2 adds `locOpenPref` (which
preference panel is open on `scrAlignment`, 0 = none), `locShowAccept` and
`locShowReject`.

### Power Fx that works and breaks here

**Breaks:** `GroupBy`; `ForAll(Sequence(n) As p, With({row: Index(...)}, Collect(...)))`;
`SortByColumns` on a Dataverse source (it wants the *logical* name `cr123_rank`,
so the display string `"Rank"` is "not found" — use `Sort(table, Column, SortOrder.Ascending)`);
`Concat` over a nested table column where bare column names must resolve in the
implicit row scope (**failed twice** — it silently returns empty, which is how the
admin answers panel came up blank; both `{Label, Text}` and `{Label, Body}`
shapes failed).

**Works:** `ClearCollect(col, ForAll(table As x, {…}))` for pure table-shaping,
`FirstN`, `Index`, `LookUp`, `Coalesce`, `With`, `RemoveIf`, `UpdateIf`, `Patch`,
`Split`, `Filter`, `Sort`, `Distinct` (with the delegation caveat below).

**Delegation caused a bug that looked like a refresh bug.** `colOverviewRows` was
built from `Distinct()` over `'RolePreference Preferences'`. `Distinct` is not
delegable on Dataverse, so it only saw the first page — default data row limit
500, against ~945 rows (105 people × up to 9 roles). New submissions are written
to the end of the table and fell outside that page, so they never appeared. The
build now runs **`colAllStaff` first** (from People, ~105 rows) and derives
`colOverviewRows` from it with delegable equality lookups only. Set **Settings →
General → Data row limit → 2000** as belt-and-braces.

---

## 7. What paste cannot carry — the manual Studio steps

Control paste creates controls and nothing else. This list is the difference
between "pushed" and "working", and it is easy to forget:

1. **Screens must exist first**, named exactly:
   `scrLanding, scrForm, scrReview, scrQuestions, scrCompleted, scrOverview,`
   `scrSubmissions, scrAlignment, scrRejection, scrAlignLocked`.
2. **Screen `Fill`** = `ColorValue("#F2F5F7")` on every screen.
3. **Screen `OnVisible`:**
   - `scrForm` → `If(varStage2Submitted, Navigate(scrCompleted))`
   - `scrQuestions` → `Set(varDraftSaved, false); If(varStage2Submitted, Navigate(scrCompleted))`
   - `scrOverview` → all of `paste/scrOverview_OnVisible.powerfx`
   - `scrSubmissions` → all of `paste/scrSubmissions_OnVisible.powerfx`
   - `scrAlignment` → `UpdateContext({locOpenPref: 0}); If(varAlignSubmitted, Navigate(scrAlignLocked))`
   - `scrRejection` → `Set(varAlignDraftSaved, false); If(varAlignSubmitted, Navigate(scrAlignLocked))`
   - `scrAlignLocked` → `If(Not varAlignSubmitted, Navigate(scrLanding))`
4. **App `OnStart`** = `paste/App_OnStart.dataverse.powerfx`, then **Run OnStart**.
5. **App `StartScreen`** = `scrLanding`, **`BackEnabled`** = `false`.
6. **The four write formulas** from `paste/Phase3-5-button-formulas.powerfx` into
   `btnConfirmContinue`, `btnSaveDraft`, `btnConfirmSubmit`, `btnConfirmDelete`.
7. **The two refresh buttons ship UNWIRED** — paste each screen's OnVisible text
   into `btnRefreshOverview.OnSelect` and `btnRefreshSubs.OnSelect`.
8. **Optional Timer** for hands-off admin refresh (manual because the Timer
   control's version id is environment-specific and a wrong one fails the whole
   paste): Insert → Input → Timer, `Duration 60000`, `Repeat true`,
   `AutoStart true`, `Visible false`, `OnTimerEnd` = the OnVisible text.
9. **Dataverse:** raise `ResponseText` to 4000; data row limit to 2000.
10. **Phase 2 only:** create `RolePreference Alignments`, add it as a data
    source, and get at least one row into it — either the real import
    (`docs/PAB-6118-export.md`) or `paste/seed-alignments-dummy.powerfx`.
    Without a row the Role Alignment card stays shut, which is correct live
    behaviour and looks like a bug in testing. The three alignment write
    formulas are **already in the pasted YAML** — no formula-bar step, unlike
    item 6.

---

## 8. Known outstanding

**Data**
- At least one Eligibilities row points at `RoleKey = "R08"`, which has no row in
  Roles. The app shows `[missing role: R08]` rather than a blank.
  `paste/diagnose-missing-roles.powerfx` walks through finding the cause (absent
  key / Excel stripping the leading zero to `R8` / trailing space) and the scope
  across all users. **Data fix, not an app fix** — and because Preferences stores
  the key rather than the name, correcting it resolves already-submitted rankings
  with no resubmission.
- `GRADE` / `AREA` / `TEAM` blank for at least one People row.
- Eligibility rows whose `EmployeeID` is not in People lock those people out
  entirely ("your account is not set up for this app yet"). The relabel file has
  a count query for this.

**Not started**
- **Phase 6 of `docs/dataverse-setup.md`: Dataverse row-level security.**
  In-app gating on `varIsAdmin` is *not* security — anyone who can open the app
  can currently read the tables.
- Converting text keys to real Lookup/Choice columns.
- `scrDetail` cleanup (orphaned file).

**Verification gap** — every Stage 1/2 screen has been pasted and rendered in
Studio at some point, but the most recent commits (word-count fix, admin refresh
restructure, missing-role fallback, refresh buttons) are verified against
`scan_paste.py` only, **not** against live data in Studio. **The three Phase 2
screens have never been pasted at all** — they are `scan_paste.py`-clean and
parse as YAML, and that is the whole of the evidence so far.

---

## 9. Phase 2 scope

From the Workstream 7 requirements (03.07.26). Stage 1 and 2 are built; item 4
is now built too (see §10). What is left:

1. **Live completion feed** — a real-time view of submissions as they land.
   Partly served by the admin tracker; needs the timer or a push mechanism.
2. **Per-person summary report** — one page per person, exportable, joining their
   ranking, answers and HR record. The full HR sheet was kept for this, and
   `paste/export-alignment-columns.powerfx` is most of the join already.
3. **Over/under-subscription analysis** — count of first/second/third preferences
   per role against the number of posts, to show which roles are contested and
   which are empty. This is the main analytical piece and needs a role-capacity
   column that does not exist yet.
4. ~~**Alignment / accept-challenge workflow**~~ — **built.** See §10.

**No admin view of the alignment responses yet.** Decisions land on
`RolePreference Alignments` and are readable from Dataverse or through
`paste/export-alignment-columns.powerfx`, but nothing in the app shows an admin
who has accepted and who has rejected. That is the obvious next screen: it is
`scrSubmissions` with a different collection behind it.

---

## 10. Phase 2 — role alignment (built)

The third loop. A person is proposed a role, reads why, and either accepts it
or says why not. It is deliberately independent of Stages 1 and 2: its own
table, its own status, its own lock, and no change to any existing formula.

### The flow

```
scrLanding  cardAlign  ──"Open form"──▶  scrAlignment
   ▲  badge reads NOT YET OPEN            top three + View answers panels
   │  / ACTION REQUIRED / COMPLETED       aligned role + 150-word reasoning
   │                                      ├─ Accept role ─▶ conAcceptOverlay ─▶ scrAlignLocked
   │                                      └─ Reject role ─▶ scrRejection
   │                                                          tick boxes + 150 words
   │                                                          ├─ Save draft (Status "Draft")
   └──────────────────────────────────────────────────────────┴─ Submit ─▶ conRejectOverlay ─▶ scrLanding
```

Once `Status = "Submitted"`, **Open form** becomes **View outcome** and the only
reachable screen is `scrAlignLocked`. Each of the three screens re-checks that
in `OnVisible`, so a stale navigation cannot get round it.

### The gates

| State | Condition | What the person sees |
|---|---|---|
| Not yet open | no Alignments row, or `AssignedRoleName` blank | card badged *NOT YET OPEN*, button disabled |
| Action required | a role is published, `Status` blank or `Draft` | card badged *ACTION REQUIRED*, **Open form** |
| Completed | `Status = "Submitted"` | card badged *COMPLETED*, **View outcome** |

`varAlignPublished` and `varAlignSubmitted` are computed once in OnStart and
then maintained by the confirm buttons, so the homepage is correct straight
after a decision without an app reload.

### Two decisions worth knowing about

**Rejection reasons are one `;`-separated string, not a child table.** It keeps
the PAB-6118 export to a single readable cell and the restore to one `Split`.
The cost: **a reason must never contain a semicolon**. `colRejectReasonList` in
OnStart is the master list — the three in there now are placeholders waiting on
Claire, and swapping them for the final wording is the whole change.

**The free-text field is read live off `rejTxt.Text`, not off a variable.**
`Classic/TextInput`'s `OnChange` fires on blur, so a person who types and then
clicks **Submit** without leaving the box would otherwise submit the previous
value. `OnChange` still sets `varAlignComments`, but only so the box repopulates
on a return visit.

### The failure mode that cost the most time

**A missing data source in OnStart breaks variables that have nothing to do
with it.** OnStart is one chained formula, and Power Fx binds table names at
author time, so `'RolePreference Alignments'` not existing is not a runtime
blank to guard against — it is a bind failure that invalidates the whole rule.
Every `Set()` in it stops registering, including the ones in section 1.

It presented as two unrelated bugs, neither pointing at the cause:

- `varIsAdmin isn't recognized` on `scrLanding`'s `conActions.Height` — a
  variable set in section 1, on a screen with no Phase 2 code in it;
- **Accept role** doing nothing at all, because `varAlignPublished` was
  undefined and the button gated itself with
  `DisplayMode: =If(varAlignPublished, ...)`, which swallows the click.

Two changes came out of it. Layout formulas no longer reference globals
sourced from Dataverse (`conActions.Height` measures `lblAdminBody`
unconditionally), and no button gates itself into silence — the Accept and
Reject guards live in `OnSelect` and `Notify` when they refuse. Neither is a
fix for the missing table; both stop it from presenting as something else.

`paste/App_OnStart.alignments-stub.powerfx` is the way out: it defines the
Phase 2 variables from literals, so the app runs correctly with the table
absent and the Role Alignment card sits in its true *NOT YET OPEN* state.

### What is still open

- **The 150-word reasonings are placeholders.** Kate/Claire fill them in through
  `export/PAB-6118_Aurora_Export_Template.xlsx`; the loop is
  `docs/PAB-6118-export.md`. Every placeholder contains the word *Placeholder* —
  grep for it to prove none reached live.
- **The three rejection reasons are dummies** pending Claire's list.
- **A decision cannot be undone from inside the app.** Re-testing means clearing
  that person's Alignments row in Dataverse. If HR need an undo, it is the same
  shape as the admin Delete on `scrSubmissions`.
- **Not verified in Studio.** Everything here passes `scan_paste.py` and parses
  as YAML, but no screen in this phase has been pasted into Studio or run
  against live data yet.

### If you build on this, read first

- **§4.5 (layout) and §4.6 (block scalars)** before editing any `.pa.yaml`.
- `paste/HOW-TO-PASTE.md` — the operational guide; keep it current, the user
  works from it.
- Run `tools/scan_paste.py` before every commit.
- New screens need a new name in `tools/gen_paste.py`'s `SCREENS` list.
- Anything analytical (item 3) will hit delegation. Aggregate in a collection
  built from a small delegable base, the way `colAllStaff` → `colOverviewRows`
  now works — do not reach for `GroupBy`, it does not compile here.
