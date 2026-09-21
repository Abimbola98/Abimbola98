# Dataverse corrections the report is waiting on

Everything here is a **data edit in Dataverse**, made through
make.powerapps.com > Tables > (table) > Edit in the data grid. None of it is a
Power BI change and none of it is a canvas-app change — the app's code is
untouched by all of this.

Each item says what the evidence is, so nothing is taken on trust. The
"Evidence" line names the report query that found it; if you disagree with an
item, run that query and look.

Status as at 21/09/2026, after the first round of corrections. Each item now
carries a **Status** line. Four are done and confirmed from the report side; one
is deliberately left pending a decision; one turned out not to be a fault at
all.

The integrity measures on the reconciliation page are what confirmed the two
deletions. Row counts could not have: people are still submitting, so new rows
arrived and masked the removals. That is the argument for the page.

---

## 1. Delete — five stale preference rows for David Ackerley

**Status: DONE and confirmed.** `Ineligible Preference Rows` reads 0. The row
count of Preferences could not have confirmed this — people are still
submitting, so new rows arrived and masked the removal — which is why the
measure exists.

**Table:** RolePreference Preferences
**Rows:** `EmployeeID = 429301`, ranks **8, 9, 10, 11, 12**
**RoleKeys:** R37, R38, R35, R39, R42

**Evidence:** `PreferenceIntegrity`. These five `(EmployeeID, RoleKey)` pairs do
not exist in Eligibility. All five are Officer (G4) roles; he is SG5.

**Why they exist.** Another colleague's Eligibility rows were filed under his
employee id. The app reads Eligibility to decide what to show, so he was
presented with 12 options — his own 7 plus her 5 — and ranked all 12 on
08/09/2026. The Eligibility side has since been corrected. Correcting
Eligibility does not retract preferences already saved against it, so the five
rows remain, correctly formed, pointing at roles he can never be given.

**He does not need to re-rank.** He has exactly 7 eligible roles and ranks 1–7
are exactly those 7. Deleting ranks 8–12 leaves a complete, contiguous, valid
ranking of everything he was entitled to choose, with his top three — the ones
he wrote justifications for — untouched.

**Until this is done** `Ranked But Not Eligible` reads 5 on the reconciliation
page. It should read 0.

---

## 2. Delete — eight test preference rows

**Status: DONE and confirmed.** `Orphaned Preference Rows` reads 0.

**Table:** RolePreference Preferences
**Rows:** `EmployeeID = 67890`, ranks 1–8
**RoleKeys:** R10, R37, R38, R45, R46, R48, R56, R65
**Created:** 25/08/2026 20:22:57, all eight at the same second, all Draft

**Evidence:** `OrphanedPreferences`. `67890` has no row in RolePreference
People, and is five characters where every real employee id is six.

**Why the existing test filter missed it.** Test accounts are excluded by grade
(`Grade = "TESTER"` on the People table). This id has no People row at all, so
there is no grade to filter on. It was created straight into Dataverse rather
than through the app.

**Harmless but worth removing.** All eight rows are Draft, and Draft is excluded
from every committed count, so no published number is wrong because of them.
They are noise on the reconciliation page.

**Also check** whether `67890` has rows in RolePreference PreferenceResponses
and delete those too. It is **not** in Eligibility — 72 distinct ids there,
72 people with `HasOptions = TRUE`, so every Eligibility id has a People row.

---

## 3. Delete — the blank test row in People

**Status: DONE and confirmed.** People reads 103 rows over 103 distinct
EmployeeIDs, down from 104.

**Table:** RolePreference People
**Row:** the one with no EmployeeID, no Grade, no Area

**Evidence:** it produces a blank category on every Grade and Area slicer, which
readers will click on and find nothing behind.

**If you would rather keep it,** set its Grade to `TESTER` and the existing
filter will exclude it. Deleting is cleaner — a row with no employee id cannot
be joined to anything and serves no purpose in the table.

---

## 4. Change — "Nortumbria" is misspelled on three roles

**Status: DONE and confirmed.** R12, R41 and R60 read Northumbria in DimRole.

**Table:** RolePreference Roles
**Rows:** R12, R41, R60
**Field:** RoleName — `Nortumbria` → `Northumbria`

**Evidence:** cross-check of the app role list against the capacity workbook.

This does not break anything in Power BI, because the model joins on RoleKey and
never on the name. It is visible to colleagues in the app and on every report
label, which is reason enough.

---

## 5. Decide, then probably delete — the stray R16 eligibility row

**Status: deliberately left in, pending Claire.** This is now correct behaviour
rather than a bug: R16 shows as demand with no post to meet it, which is a true
statement about the data. It must not be read as a capacity finding until Claire
confirms whether the role is real.

It is also the likeliest explanation for the one-row discrepancy between
Eligibility (451 rows, 73 people) and Claire's final options list (450 rows, 73
people). Filter Eligibility to `RoleKey = R16` to confirm it is a single row.

**Table:** RolePreference Eligibility
**Rows:** any with `RoleKey = R16`

**Evidence:** R16 carries zero posts in the capacity workbook, and Claire's
final options list grants it to nobody.

Somebody can currently rank a role that has no post to give. The what-if
correctly reports that as unmeetable demand, which is honest but is reporting a
data fault as a finding. **Confirm with Claire that R16 is genuinely not on
offer before deleting** — if it is real and simply has no post count yet, the
fix is in the capacity workbook instead.

---

## 6. ~~Check, and probably add — Stage 2 answers for the three manual entries~~

**Status: NOT A FAULT. Nothing to do.** `DiagPersonTrace` found six Responses
rows for each of the three — two questions across three justified roles,
complete. The hypothesis below was wrong and is kept only so the reasoning is
not repeated.

The real cause of those people appearing wrong was unrelated: the query named
PreferenceWide held ResponseWide's code, so every respondent was counted about
three times and the preference-name columns were blank. See BUILD.md 9.12.

**Table:** RolePreference PreferenceResponses
**People:** 436515, 434141, 409059

The three forms that were entered by hand contained both a ranking **and**
written justifications. The rankings are confirmed present in the Preferences
table. If the justifications were never typed into the PreferenceResponses
table, those three people are correct on every Stage 1 visual and absent from
every Stage 2 one — free text, themes, word counts, completion.

**Run `DiagPersonTrace` before doing anything here.** Stage 5 in its output is
this table. If it reads 0, the answers are missing; if it reads 6 (two questions
across three justified roles), they are there and the problem is elsewhere.

Each person needs **two rows per top-three role** — `QIndex = 0` for "why this
preference" and `QIndex = 1` for "skills and experience" — so six rows each,
matching the QuestionText the app stores.

---

## Not data fixes — questions for the business

These cannot be resolved by editing a row. They need somebody to decide.

| Question | Why it matters |
|---|---|
| R32 / R40 carry contradictory annotations in the capacity workbook | The post counts feed every over/under-subscription number on the report |
| Three capacity rows have `?` instead of a role key | They hold posts that can never be allocated, because nothing can rank them |
| Is R16 on offer at all | See item 5 |
| `G6 TL` and `G6 SA` — one grade or two | Changes the grade breakdown and the line-manager count |
| Headcount is 104 in People, 110 elsewhere | Six people are either missing from the system or not in scope, and nobody has said which |
| Is SG6 the right definition of "line manager" | `Total Line Managers` is a provisional guess and is labelled as one in BUILD.md |

---

## Not for this repository — the app-side root cause

Item 1 happened because Eligibility was filed under the wrong employee id, and
nothing catches it. Two questions belong with whoever owns the canvas app:

- should the app validate a submitted preference against the person's current
  Eligibility, rather than trusting what it rendered
- should correcting somebody's Eligibility invalidate preferences that no longer
  match it

`PreferenceIntegrity` makes the consequence visible on the reconciliation page.
It cannot prevent it.
