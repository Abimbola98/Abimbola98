# Paste into Power Apps Studio, page by page (Code View)

> New to this build? Read [`../docs/HANDOFF.md`](../docs/HANDOFF.md) first — it
> covers the YAML format, the layout model and the paste hazards that shaped
> every file here. Regenerate with `python3 tools/gen_paste.py` and verify with
> `python3 tools/scan_paste.py`.

These files let you build the app by **pasting one screen at a time** using
Studio's **Code View** (public preview). They are the paste-ready form of the
`../Src/*.pa.yaml` source — dedented to the clipboard format Studio expects
(a top-level list of controls), because the `.pa.yaml` files themselves are
read-only Git source and can't be pasted onto a page.

| File | Paste where |
|---|---|
| `App_OnStart.powerfx` | App object → **OnStart** formula bar |
| `App_OnStart.dataverse.powerfx` | App object → **OnStart** (the live Dataverse version) |
| `scrOverview_OnVisible.powerfx` | **scrOverview → OnVisible** |
| `scrSubmissions_OnVisible.powerfx` | **scrSubmissions → OnVisible** |
| `one-off-purge-withdrawn.powerfx` | temporary button, run once — see the file |
| `diagnose-missing-roles.powerfx` | read-only diagnostics — see the file |
| `one-off-relabel-eligibilities.powerfx` | temporary button, run once — see the file |
| `scrLanding.controls.yaml` | the **scrLanding** screen node |
| `scrForm.controls.yaml` | the **scrForm** screen node (incl. continue overlay) |
| `scrReview.controls.yaml` | the **scrReview** screen node |
| `scrQuestions.controls.yaml` | the **scrQuestions** screen node (incl. submit overlay) |
| `scrCompleted.controls.yaml` | the **scrCompleted** screen node |
| `scrOverview.controls.yaml` | the **scrOverview** screen node (all-staff tracker) |
| `scrSubmissions.controls.yaml` | the **scrSubmissions** screen node (incl. delete overlay) |
| `scrReview.controls.yaml` | includes the **change-ranking warning** overlay |
| `scrDetail.controls.yaml` | *(unused — role-detail pages were dropped; nothing navigates here)* |
| `scrAlignment.controls.yaml` | the **scrAlignment** screen node (incl. accept overlay) |
| `scrRejection.controls.yaml` | the **scrRejection** screen node (incl. submit overlay) |
| `scrAlignLocked.controls.yaml` | the **scrAlignLocked** screen node |
| `Phase2-alignment-formulas.powerfx` | reference copy of the three alignment writes — already in the YAML |
| `seed-alignments-dummy.powerfx` | temporary button, run once — dummy alignments for testing |
| `export-alignment-columns.powerfx` | temporary button — builds the PAB-6118 export collection |

## Control versions in this build (IMPORTANT)

Studio's paste **silently drops any control whose type id (and version) it
doesn't recognise** — that's why early pastes produced an empty container.
Control ids are **version-pinned per environment**. This scaffold is built on
the two ids confirmed in your environment:

- `GroupContainer@1.5.0` — every layout box, card, pill background, the green
  strip, and the overlay containers.
- `Label@2.5.1` — all text. **Buttons are Labels with `OnSelect`** and the
  overlay **scrim is a Label** (Fill + OnSelect), so no Button/Rectangle ids
  are needed.

➡ **`scrLanding` uses only these two ids, so it pastes in full.** Start there.
> If you get a `PA2108 'AutoWidth'` (or `LayoutMode`/`Radius`) error, you're
> pasting an **old copy** — re-pull this file and re-copy it.

### Property rules confirmed for this build (so paste doesn't error)
- `GroupContainer@1.5.0`: **no `LayoutMode`** (the `AutoLayout`/`ManualLayout`
  variant already sets it). Valid: `LayoutDirection`, `LayoutGap`,
  `LayoutJustifyContent`, `LayoutAlignItems`, `LayoutWrap`, `LayoutOverflowY`,
  `Fill`, `Border*`, `Radius*`, `Padding*`, `FillPortions`.
- `Label@2.5.1`: **no `AutoWidth`, no `Radius*`** (so pills/badges render
  **square** — wrap in a container later if you want them rounded). Valid:
  `Text`, `Fill`, `Color`, `Border*`, `AutoHeight`, `Width`, `Align`,
  `VerticalAlign`, `Padding*`, `OnSelect`, `FillPortions`.
- **Sizing:** every auto-layout child has `FillPortions: =0` so it keeps its
  own height (otherwise children stretch to fill); width-less labels get
  `Width: =Parent.Width` (vertical parent) or `FillPortions: =1` (horizontal).
- **Hover/Pressed FILL comes through paste; hover text/border colour does not.**
  `Label@2.5.1` supports `HoverFill` and `PressedFill` in Code View, so those
  are **baked into every button in these paste files** — the button
  hover/press background works straight from paste, no manual step. The modern
  Label has **no** serializable `HoverColor`/`PressedColor`/`HoverBorderColor`/
  `PressedBorderColor` (they don't appear in Studio's View code), so button
  text/border colour stays constant on hover — the fill change is the signal.
- **Layout rule: a container's `Height` is the sum of its children.** Auto-layout
  containers do not grow to fit their contents, so every fixed height in these
  files is either a literal sum of the child heights or a formula over them
  (e.g. `Height: =qsnQ1a.Height + 176`, `Height: =cmpSec1.Height + …`). Text that
  wraps — question wording, 150-word answers, the privacy statement — sits in an
  `AutoHeight: =true` label whose `.Height` feeds its parent, so nothing clips at
  any window width. **This only works while control names stay unique**: Studio
  renames a pasted control that clashes with an existing one (`lblFoo_1`) and the
  parent's height formula would then point at the wrong control. Paste each screen
  onto an *empty* screen node.
- **A gallery sized to `N * TemplateSize` still clips its last row** — the
  default `TemplatePadding` adds unmetered space between items. Every gallery
  that is meant to show its whole list sets `TemplatePadding: =0` and adds a
  little slack (`Height: =CountRows(col) * 88 + 16`), so it never needs its own
  scrollbar.
- **Answer boxes carry `MaxLength: =2000`** to match the Dataverse
  `ResponseText` column. Without it a long paste reached the server and came
  back as `Network error when using Patch function: Length must be between 0
  and 2000` — after some rows had already been written.
- **One scrolling surface per screen.** Only `conContent` has
  `LayoutOverflowY: =LayoutOverflow.Scroll`; `conRoot` does not, and nested
  galleries are sized to their content. Two nested scroll regions plus a gallery
  is what produced "this screen has three scroll bars".
- **No duplicate property keys in one `Properties:` block** — Studio reports
  `PA1001 … Duplicate name 'X' used at …`. Easy to introduce when a sizing
  change adds e.g. `FillPortions` to a control that already had it; the
  generator now scans for this before every push.
- **Multi-line formula formatting (avoids `PA1001 YamlInvalidSyntax`):** inside
  `|-` block-scalar formulas, no line may **start** with `SomeName: value`, and
  record literals `{...}` must stay on **one line** (never a bare `{` or `}` on
  its own line). The deserializer re-scans formula text and reads a
  `Name: `-leading line as a YAML mapping ("found invalid mapping"). Long
  strings are split into `Set(varX, "...")` fragments concatenated with `&`.
- **Expected red ✗ on landing until all 10 screens exist:** the action buttons
  call `Navigate(scrForm/scrReview/scrCompleted/scrOverview/scrAlignment/scrAlignLocked)`;
  those resolve only once the target screens are created (step 3 below). Create
  all ten screens first and the markers clear.
- **No Checkbox control in the pinned set**, so the rejection reasons are
  **Labels acting as tick boxes**: the box Label's `Text` is a tick when
  `ThisItem.Chosen`, and both it and the reason text flip it with
  `Patch(colRejectReasons, ThisItem, {Chosen: Not ThisItem.Chosen})`. Adding a
  real Checkbox would mean pinning a sixth control id — and a wrong `@x.y.z`
  fails the whole paste.

**All five control ids are now version-stamped for this build**, so every
screen pastes whole:

| Control id | Used for |
|---|---|
| `GroupContainer@1.5.0` | layout boxes, cards, pill backgrounds, strips, overlays |
| `Label@2.5.1` | all text; buttons (Label + `OnSelect`); the overlay scrim |
| `Gallery@2.15.0` (`Variant: Vertical`/`Horizontal`) | roles list, ranking, question sections, overview rows, bullet lists |
| `Classic/DropDown@2.3.1` | form rank picker |
| `Classic/TextInput@2.3.2` | Stage-2 answer boxes (supports `Radius*`, unlike Label) |

If a later Power Apps update bumps any version, re-grab it from **View code** on
a freshly inserted control and re-stamp (a wrong `@x.y.z` can fail the paste, so
match it exactly).

## One-time setup
1. **Turn on Code View.** Power Apps Studio → **Settings → Upcoming features →
   Preview** → enable **Code View** (a.k.a. "View/Paste code"). Reload Studio.
   Grant the browser **clipboard permission** the first time you paste.
2. **Create a blank canvas app**, responsive: **Settings → Display →** Scale to
   fit **Off**, Lock aspect ratio **Off**.
3. **Create the screens and name them exactly** (the `Navigate()` calls target
   these names — they must match):
   `scrLanding, scrForm, scrReview, scrQuestions, scrCompleted, scrOverview, scrSubmissions,`
   `scrAlignment, scrRejection, scrAlignLocked`.
   The last three are **Phase 2 — role alignment**: the person reads the role
   they have been aligned to and either accepts it or tells us why not.
   `scrSubmissions` is new — the admin submissions table and answer panel moved
   there off `scrOverview`, which could not fit one window at 100% zoom.
   `scrDetail` is no longer reachable and does not need to exist.
4. **App properties:** set **StartScreen = `scrLanding`**, **BackEnabled = `false`**.

## Paste the App.OnStart
1. Select the **App** object (top of the tree) → property dropdown → **OnStart**.
2. Open `App_OnStart.powerfx`, copy **all** of it, paste into the formula bar.
   *(The leading `=` is already removed for the formula bar.)*
3. Right-click the **App** object → **Run OnStart** so the seed collections exist
   while you design. Re-run it whenever you reopen the app.

## Paste each screen
For every screen:
1. In the **tree view**, select the screen node (e.g. **scrForm**).
2. Right-click → **Paste code** (or **Ctrl+V**).
3. Open the matching `scr*.controls.yaml`, **Select All → Copy**, then paste.
   The whole `conRoot` container (and, for scrForm/scrQuestions, the overlay)
   is created with all its children in one go.
4. Set the **screen's own properties** (paste only creates controls, not screen
   props):
   - **Fill** = `ColorValue("#F2F5F7")` on every screen.
   - **scrForm → OnVisible** = `If(varStage2Submitted, Navigate(scrCompleted))`
     — only a fully submitted form is final; the ranking stays editable (draft)
     until then, so users can return and change their choices.
   - **scrQuestions → OnVisible** = `Set(varDraftSaved, false); If(varStage2Submitted, Navigate(scrCompleted))`
     — stops a user who already submitted Stage 2 from re-answering.
   - **scrOverview → OnVisible** = paste the whole of
     `scrOverview_OnVisible.powerfx` — refreshes the Dataverse tables and
     rebuilds the admin collections on every visit, so admins never need to
     reload the app to see new submissions.
   - **Both admin screens carry a `↻ Refresh data` button that ships UNWIRED.**
     Paste the same screen OnVisible text into `btnRefreshOverview.OnSelect`
     (scrOverview) and `btnRefreshSubs.OnSelect` (scrSubmissions). The rebuild
     cannot live in the pasted YAML: its record literals put `Name: value` at the
     start of a line, which is exactly the shape that triggers `PA1001
     YamlInvalidSyntax`. Until you do this the button says so when pressed.
     OnVisible only fires on navigation — an admin sitting on the page needs the
     button (or the optional timer below) to see a submission that lands while
     they are watching.
   - **scrSubmissions → OnVisible** = paste the whole of
     `scrSubmissions_OnVisible.powerfx` — the same refresh + rebuild as
     scrOverview, plus a collapse of any open answer panel. **Both admin screens
     need their own OnVisible**; neither may assume the other was visited first,
     which is why data looked stale until you hit the browser refresh.
   - **scrAlignment → OnVisible** = `UpdateContext({locOpenPref: 0}); If(varAlignSubmitted, Navigate(scrAlignLocked))`
     — every answer panel starts closed, and anyone who has already responded
     is bounced to the locked view.
   - **scrRejection → OnVisible** = `Set(varAlignDraftSaved, false); If(varAlignSubmitted, Navigate(scrAlignLocked))`
   - **scrAlignLocked → OnVisible** = `If(Not varAlignSubmitted, Navigate(scrLanding))`
     — the locked page is meaningless before a decision has been submitted.

Repeat for each screen. Then **Run OnStart** again and press **Play** to test:
Landing → Form (the seeded **1 / 1** duplicate shows the amber validation) →
Continue (locks Stage 1) → Review → Stage 2 → Submit (locks) → Completed; and
**Submissions Overview** (expand a row, soft **Withdraw**).

## Phase 2 — role alignment

The three alignment screens need one thing paste cannot give them: **a row on
`RolePreference Alignments`** with a role name in it. Until that exists the
Role Alignment card on the homepage stays shut and says *NOT YET OPEN*, which
is the correct live behaviour and looks like a bug in testing.

1. **Create the table** — schema in
   [`../docs/dataverse-setup.md`](../docs/dataverse-setup.md), *Alignments*.
   `AssignedReason`, `RejectReasons` and `RejectComments` must be **4000
   characters**, for the same reason `ResponseText` is.
2. **Add it as a data source** alongside the other five.
3. **Re-paste `App_OnStart.dataverse.powerfx`** — it has a new section 4b that
   reads the alignment and builds `colRejectReasons` — then **Run OnStart**.
4. **Get some data in**, either
   [`seed-alignments-dummy.powerfx`](seed-alignments-dummy.powerfx) on a
   temporary button (dummy alignments for testing), or the real import from
   Kate/Claire's spreadsheet — [`../docs/PAB-6118-export.md`](../docs/PAB-6118-export.md).
5. **Walk it through:** Landing (card now badged *ACTION REQUIRED*) → **Open
   form** → scrAlignment → open and close a *View answers* panel → scroll to
   the aligned role and its reasoning → **Reject role** → tick two reasons,
   type some words, **Save draft**, navigate away and back (the ticks and the
   text come back) → **Submit** → confirm → back on the homepage the card reads
   *COMPLETED* → **View outcome** shows the locked page with the reasons and
   the free text and nothing editable.
6. **Test the accept path with a second person** — a decision cannot be undone
   from inside the app, so re-testing means clearing that person's Alignments
   row in Dataverse (`Decision`, `Status`, `RejectReasons`, `RejectComments`
   back to empty).

**The three write formulas are baked into the pasted YAML** — unlike Phase 3–5,
there is no manual formula-bar step here. [`Phase2-alignment-formulas.powerfx`](Phase2-alignment-formulas.powerfx)
is the reference copy for when one has to be re-typed.

> The `*.controls.yaml` snippets are intentionally **comment-free and use only
> block-style YAML** — Studio's Code View parser rejects `#` comments and
> single-quoted/flow values, which is what causes `PA1001 … YamlInvalidSyntax`.
> Always copy from `paste/*.controls.yaml`, **not** from `../Src/*.pa.yaml`
> (the Src files keep comments for Git/pack and won't paste).

## Optional: hands-off auto-refresh (30 seconds of manual setup)

The `↻ Refresh data` button covers an admin who is watching the page. For it to
update by itself, add a timer — this is a manual step because the Timer control's
version id is environment-specific and a wrong `@x.y.z` fails the whole paste:

1. On **scrOverview**, **Insert → Input → Timer**.
2. Set **Duration** `60000`, **Repeat** `true`, **AutoStart** `true`,
   **Visible** `false`.
3. Paste the screen's OnVisible text into the timer's **OnTimerEnd**.
4. Repeat on **scrSubmissions**.

## Data row limit

**Settings → General → Data row limit → 2000.** The default of 500 is below the
~945 rows that 105 people ranking up to 9 roles each produce in
`RolePreference Preferences`. The admin build no longer depends on it — it now
derives from People and uses only delegable equality lookups — but any
non-delegable formula added later would silently see a partial table.

## Likely friction & fixes
- **`PA1001 … YamlInvalidSyntax; … found invalid mapping`.** The pasted text
  contained a `#` comment, a single-quoted value, or a `{…}` flow mapping. Use
  the `paste/*.controls.yaml` files in this folder (already cleaned) — don't
  paste the `../Src` files or hand-add comments.
- **"The clipboard doesn't contain any YAML code to paste."** You must copy the
  file's **text** to the OS clipboard and paste onto a **tree node** (not the
  canvas), with browser clipboard permission granted.
- **Control type rejected on paste.** These snippets use unversioned control IDs
  (`Label`, `Classic/Button`, `Classic/DropDown`, `Classic/TextInput`,
  `GroupContainer`, `Gallery`, `Rectangle`). If your environment wants a
  version/different id, drop a control of that type on a scratch screen →
  right-click → **View code** to see the exact `Control:` id (e.g.
  `Label@2.x.y`) and match it in the snippet.
- **Duplicate control names across screens.** Studio auto-renames clashes (e.g.
  `conHeaderBar_1`). Harmless here — formulas use `Parent`/`Self`/`ThisItem`/
  variables/collections, never another control's literal name.
- **Galleries look empty / errored at design time.** They bind to the OnStart
  collections — **Run OnStart** first.
- **Data:** everything runs on the seed collections offline. To go live, repoint
  each gallery/write to Dataverse and wire identity + admin per the main
  [`../README.md`](../README.md) (sections 2–3). In-app gating is **not**
  security — apply Dataverse row-level security.

## Want a single-import instead?
Pasting is page-by-page by design. If you'd rather import the whole app at once,
use **`pac canvas pack`** to build an `.msapp` from `../Src`, or connect the
solution to this repo via **Git integration** — see [`../README.md`](../README.md)
section 4.
