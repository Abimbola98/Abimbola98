# Connecting Aurora — Role Preference to Dataverse

The app's screens all bind to **in-memory collections** (`colRanks`,
`colLockedRanking`, `colAnswers`, …). That stays true after connection — we
load those collections **from Dataverse** in `App.OnStart` and write back at
four points (Stage-1 lock, Save draft, Stage-2 submit, admin Withdraw). No
gallery or label bindings change, so everything you've pasted and styled is
untouched.

> **Your environment's table names:** the tables are prefixed
> **`RolePreference `** (e.g. *RolePreference Roles*). Names with spaces must
> be single-quoted in Power Fx — `'RolePreference Roles'` — and every formula
> in this guide and in `App_OnStart.dataverse.powerfx` is already written that
> way. If the Data pane shows a slightly different name (e.g. a different
> plural), use **exactly** what the Data pane shows. Column names are
> unaffected by the prefix.

Work through the phases in order; the app keeps working after every phase.

---

## Phase 0 — Create the solution and tables

In [make.powerapps.com](https://make.powerapps.com) (your Dataverse
environment): **Solutions → New solution** (e.g. `AuroraRolePreference`), then
create these tables inside it. Add the canvas app to the same solution.

Keep the app in the same solution as the tables for clean ALM
(export/import between Dev/Test/Prod).

> **v1 keeps things simple:** plain **Text** keys (`RoleKey`, `EmployeeID`)
> and Text status columns instead of Choices/Lookups. That matches the
> collection shapes exactly, so the formulas below drop straight in. Converting
> to proper Lookup/Choice columns is a later hardening step.

### Roles
| Column (display name) | Type | Notes |
|---|---|---|
| RoleName | Text — **primary** | e.g. "Governance & Decision Support" |
| RoleKey | Text | short key: `gov`, `perf`, `stake`, `risk`, `res` |
| ShortDescription | Text | card strapline |
| Purpose | Multiline text | scrDetail "Purpose" |
| Responsibilities | Multiline text | **one bullet per line** |
| Requirements | Multiline text | **one bullet per line** |
| GradeContext | Text | e.g. "Typically SG6." |
| Active | Yes/No | default Yes |

### People
| Column | Type | Notes |
|---|---|---|
| Name | Text — primary | display name |
| EmployeeID | Text | e.g. "60412" |
| Email | Text | **lower-case UPN** — the sign-in key |
| Grade / Area / Team | Text | |
| IsAdmin | Yes/No | drives `varIsAdmin` (in-app gate only — see Phase 6) |

### Eligibility
| Column | Type |
|---|---|
| Name | Autonumber (primary) |
| EmployeeID | Text |
| RoleKey | Text |

### Preferences  *(written at Stage-1 lock)*
| Column | Type |
|---|---|
| Name | Autonumber (primary) |
| EmployeeID / RoleKey | Text |
| Rank | Whole number |
| SubmittedBy | Text |
| SubmittedOn | Date and time |
| Stage1Status | Text — `Submitted` / `Withdrawn` |

### PreferenceResponses  *(skeleton written at Stage-1 lock; answers patched after)*
| Column | Type |
|---|---|
| Name | Autonumber (primary) |
| EmployeeID / RoleKey | Text |
| QIndex | Whole number — 0 = "why this preference", 1 = "skills/experience" |
| QuestionText | Multiline text |
| ResponseText | Multiline text |
| SubmittedOn | Date and time |
| Stage2Status | Text — `Draft` / `Submitted` |

*(RoleQuestions is currently unused — Workstream 7 standardised the questions
— so don't create it unless role-specific questions return.)*

**Seed the data:** enter the 5 roles (copy text from `Src/App.pa.yaml`
section 2, putting each Responsibilities/Requirements bullet on its own line),
your pilot People rows (with your own row, `IsAdmin = Yes`), and Eligibility
rows linking people to roles.

---

## Phase 1 — Add the data sources to the app

In Studio: **Data (cylinder icon) → Add data →** search `RolePreference` and
add all five tables (**RolePreference Roles / People / Eligibility /
Preferences / PreferenceResponses**).

Also set **Settings → General → Data row limit = 2000** (delegation buffer
for the admin overview).

---

## Phase 2 — Swap App.OnStart

Replace the formula bar contents with
**`paste/App_OnStart.dataverse.powerfx`** (formula-bar-ready, `=` stripped).
It does, in order:

1. `varUser` from `LookUp('RolePreference People', Email = Lower(User().Email))`; `varIsAdmin`
   from the People table's `IsAdmin` column.
2. `colRoles` from Roles (bullets split on line breaks).
3. `colRanks` from Eligibility ⋈ Roles for this user (all ranks 0 = unranked;
   fresh error panel state).
4. **Resume state** from Preferences / PreferenceResponses: rebuilds
   `colLockedRanking` + `colAnswers` and derives
   `varStage1Submitted`/`varStage2Submitted` + dates — so a returning user
   lands exactly where they left off (Landing routes them automatically).
5. Admin: builds `colOverviewRows` (only when `varIsAdmin`).

> **Column-name note:** `Split()`/`Distinct()` return a one-column table whose
> column is `Value` in current Power Fx (older builds: `Result`). If the
> formula bar flags `Value` in the marked spots, swap it to `Result`.

Keep the old seed OnStart (`paste/App_OnStart.powerfx`) — it's still the
offline/demo version if you ever need to work disconnected.

## Phase 3 — Stage-1 lock writes to Dataverse

`scrForm → btnConfirmContinue.OnSelect`: **after** the existing
`ClearCollect(colAnswers, …)` builder and **before** `Set(varStage1Submitted,
true)`, add:

```
Collect('RolePreference Preferences', ForAll(colLockedRanking As r, {EmployeeID: varUser.EmpId, RoleKey: r.RoleKey, Rank: r.Rank, SubmittedBy: Lower(User().Email), SubmittedOn: Now(), Stage1Status: "Submitted"}));
Collect('RolePreference PreferenceResponses', ForAll(colAnswers As a, {EmployeeID: varUser.EmpId, RoleKey: a.RoleKey, QIndex: a.QIndex, QuestionText: a.QuestionText, ResponseText: "", Stage2Status: "Draft"}))
```

(`Collect` on a Dataverse table **creates** the rows; the skeleton Draft
response rows are what Save draft patches into.)

## Phase 4 — Save draft & Stage-2 submit write-through

`scrQuestions → btnSaveDraft.OnSelect` becomes:

```
ForAll(colAnswers As a, Patch('RolePreference PreferenceResponses', LookUp('RolePreference PreferenceResponses', EmployeeID = varUser.EmpId And RoleKey = a.RoleKey And QIndex = a.QIndex), {ResponseText: a.Answer}));
Set(varDraftSaved, true)
```

`scrQuestions → btnConfirmSubmit.OnSelect` — replace the
`ClearCollect(colPreferenceResponses, …)` line with:

```
ForAll(colAnswers As a, Patch('RolePreference PreferenceResponses', LookUp('RolePreference PreferenceResponses', EmployeeID = varUser.EmpId And RoleKey = a.RoleKey And QIndex = a.QIndex), {ResponseText: a.Answer, Stage2Status: "Submitted", SubmittedOn: Now()}));
```

keeping the `Set(varStage2Submitted…)`/`Navigate` lines that follow.

> If the environment's compiler rejects `ForAll(… Patch(…))` (it has been
> picky about some `ForAll` side-effect combos), fall back to six sequential
> `Patch` calls — there are always exactly 6 answer rows (3 roles × 2
> questions).

## Phase 5 — Admin: Withdraw writes through

`scrOverview → btnWithdraw.OnSelect` becomes:

```
UpdateIf('RolePreference Preferences', EmployeeID = ThisItem.EmpId, {Stage1Status: "Withdrawn"});
Patch(colOverviewRows, ThisItem, {Status: "Withdrawn"})
```

(the second line keeps the UI in sync without a full overview reload — note
`colOverviewRows` rows now carry `EmpId`, added by the new OnStart).

## Phase 6 — Security (before real data goes in)

In-app gating (`varIsAdmin`, hidden admin card) is **not** security. In
**Power Platform admin center → environment → security roles** create:

- **Aurora User** — Roles/Eligibility/People: Read (org). Preferences /
  PreferenceResponses: Create + Read/Write **User-level (own records only)**.
- **Aurora Admin** — the above plus org-wide Read/Write on Preferences /
  PreferenceResponses.

Because rows are created by the signed-in user, Dataverse row ownership makes
"own records only" work automatically. Assign roles to the pilot group, share
the app, and test that a non-admin genuinely cannot read others' rows (e.g.
via the app or Excel/API) — that's the boundary that matters.

## Phase 7 — Test checklist

1. Fresh user (no Preferences rows): Landing → Form shows their eligible
   roles, all unranked; validation and Continue gating work.
2. Stage-1 lock: Preferences rows + 6 Draft PreferenceResponses rows appear
   in Dataverse; app navigates to Review.
3. Close the app, reopen: lands on Review (state resumed from Dataverse).
4. Stage 2: type answers, **Save draft**, close, reopen → answers restored.
5. Submit: response rows flip to `Submitted`; reopen lands on Completed.
6. Admin: overview lists submitters; expand shows answers; Withdraw flips
   `Stage1Status` in Dataverse and mutes the row. Non-admin sees no admin
   card **and** (per Phase 6) cannot read others' rows even outside the app.
7. Word-limit: >150 words blocks Submit (server-side revalidation is a later
   hardening item — the limit is UX-enforced only).

### Delegation note
`Filter('RolePreference Preferences', EmployeeID = …)` etc. are delegable to Dataverse. The
admin overview iterates in-memory (`ForAll`/`Distinct`) over downloaded rows —
fine for hundreds of staff at the 2000-row setting; if the population is
larger, page it by Area or move the aggregation to a Dataverse view.
