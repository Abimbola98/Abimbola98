# Aurora — Role Preference (Power Apps Canvas, YAML source scaffold)

An **importable scaffold** of the Aurora Role Preference canvas app, generated
from the interactive mockup `Aurora_Role_Preference.dc.html`. It is written in
the modern Power Platform **`.pa.yaml`** source format (Git-integration /
"canvas apps as code"): one app-level file plus one file per screen.

> ⚠️ **This is a scaffold, not a validated app.** It is built to be imported
> and then refined in Power Apps Studio. Some control IDs, variant names and
> property names in the `.pa.yaml` schema are resolved by Studio at import and
> a few values below will need confirming/tuning. Everything that needs a
> human in Studio is listed under [Manual fix-up](#3-manual-fix-up-in-studio).

```
aurora-role-preference/
├─ README.md
└─ Src/
   ├─ App.pa.yaml          # StartScreen + OnStart (all seed collections)
   ├─ scrLanding.pa.yaml   # 1) Landing
   ├─ scrForm.pa.yaml      # 2) Preference form (Stage 1) + continue overlay
   ├─ scrDetail.pa.yaml    # 3) Role detail
   ├─ scrReview.pa.yaml    # 4) Ranking review (Stage 1 submitted)
   ├─ scrQuestions.pa.yaml # 5) Supporting questions (Stage 2) + submit overlay
   ├─ scrCompleted.pa.yaml # 6) Completed confirmation (locked)
   └─ scrOverview.pa.yaml  # 7) Submissions overview (admin)
```

All eight files are valid YAML and the control tree has been structurally
verified (7 screens; controls: GroupContainer ×87, Label ×123, Classic/Button
×24, Gallery ×14, Rectangle ×11, Classic/DropDown ×1, Classic/TextInput ×1).

---

## Design fidelity (extracted from the dc.html)

**Palette** (reproduced exactly from the inline styles via `ColorValue("#…")`):

| Token | Hex | Used for |
|---|---|---|
| EA navy | `#002B54` | header bar, headings, rank circle, primary buttons |
| EA green | `#008531` | header strip, primary CTA, success banner, accents |
| green hover / dark | `#00712A` / `#006B27` | CTA hover, "All staff"/submitted text |
| page bg | `#F2F5F7` | screen fill |
| card / border | `#FFFFFF` / `#DCE2E8` | cards, panels |
| text / muted | `#1F2933` / `#5B6670` · `#475160` · `#3A4651` | body & labels |
| link blue | `#0E6FA8` | text links, "Role details ›" |
| accent cyan | `#54BCE7` | stage pills, focus, admin accent |
| blue tint / border | `#EBF6FB` / `#C7E6F4` | stage pills, instruction callout |
| admin pill | `#E1F2FB` / `#BBE2F4` | restricted badges |
| green tint | `#E4F3EA` / `#B5DEC5` | "All staff" pill, draft-saved banner, submitted pills |
| amber error | `#F78913` · `#FDF1E3` · `#F4C68A` · `#8A4B00` | duplicate-rank border/fill, error panel |
| read-only field | `#EEF2F5` / `#D4DCE2` | locked detail boxes |
| input border | `#9AA7B2` | dropdown / text input |
| disabled button | `#C8CFD5` / `#79838C` | disabled Continue / Submit |
| withdrawn-muted | `#FAFBFC` · `#EAEDEF` / `#4A5560` | withdrawn overview rows + pill |

**Pills/badges** are `Label`s with `Fill` + `RadiusTopLeft/TopRight/BottomLeft/
BottomRight` + (where present) `BorderColor`/`BorderThickness` — no CSS.
**Cards** are `GroupContainer`s carrying their own `Fill`/`Border`/`Radius`.
**Layout** is 100 % responsive: every screen is a root vertical
`GroupContainer (AutoLayout)` with `LayoutOverflowY = Scroll`, a centered
content column constrained to `Min(Parent.Width-48, 1120)`. No control is
positioned with fixed X/Y except the two full-screen overlay scrims.

---

## 1. Screen + key-control map

Each screen file is a `Screens:` document with one root `conRoot`
(GroupContainer/AutoLayout), a shared **header** (`conHeaderBar` navy +
`recGreenStrip` green 4px), and a centered `conContent` column.

### scrLanding.pa.yaml — Landing
| Element | Control(s) |
|---|---|
| EA header (org + app name + user/grade) | `conHeaderBar` → `lblLogo`, `lblOrg`, `lblAppName`, `lblUserName`, `lblUserMeta` |
| Welcome card (Name, Grade, Area, Team, Last logged in) | `cardWelcome` → `lblWelcomeTitle`, `conWelcomeGrid` (`lblGradeVal`/`lblAreaVal`/`lblTeamVal`), `lblLastLogin` |
| "My Preference Form" (all staff) | `cardForm` → `lblFormBadge` ("ALL STAFF"), `btnOpenForm` — **routes by progress** (`If(varStage2Submitted→scrCompleted, varStage1Submitted→scrReview, scrForm)`) |
| "Submissions Overview" (admin only) | `cardAdmin` (`Visible = varIsAdmin`) → `lblAdminBadge`, `btnOpenOverview` |

### scrForm.pa.yaml — Preference form (Stage 1)
| Element | Control(s) |
|---|---|
| Back-to-home, stage pill, title | `btnBackHome`, `lblStagePill`, `lblFormTitle` |
| Read-only user details | `cardDetails` → `galUserFields` (Horizontal gallery of Name/Employee ID/Grade/Area as **labels**, not inputs — immutable) |
| Instruction callout | `calloutInstruction` |
| **Error list** | `panelErrors` (`Visible = CountRows(colFormErrors)>0`) → `galErrors` bound to `colFormErrors` |
| **Eligible-roles ranking grid** | `cardRoles` → `galRoles` (`Items = colRanks`); per row `lblRoleName`, `lblRoleDesc`, `btnRoleDetails`, `lblDupMsg`, **`drpRank`** |
| Duplicate detection | `galRoles.TemplateFill`, `drpRank.BorderColor/BorderThickness`, `lblDupMsg.Visible` all use `CountRows(Filter(colRanks, Rank = ThisItem.Rank))>1` |
| Continue gating | `btnContinue` `DisplayMode/Fill` from `CountRows(colFormErrors)>0`; opens overlay |
| **Continue overlay** | `conContinueOverlay` (sibling of conRoot) → `recScrim` + `dlgContinue` (`btnKeepEditing`, `btnConfirmContinue` = **lock Stage 1**) |

### scrDetail.pa.yaml — Role detail
| Element | Control(s) |
|---|---|
| Origin-aware Back | `btnBackTop` / `btnBackBottom` — label + `Navigate` switch on `varDetailOrigin` (form/review/questions) |
| Purpose / Responsibilities / Requirements / Grade context | `cardProfile` → `lblPurpose`, `galResp`, `galReq` (bulleted galleries over `LookUp(colRoles…).Responsibilities/Requirements`), `lblGradeCtx` |

### scrReview.pa.yaml — Ranking review (Stage 1 submitted)
| Element | Control(s) |
|---|---|
| Stage pill, "Ranking submitted on <date>" | `lblStagePill`, `lblSub` (`varStage1Date`) |
| Locked ranking (rank circle + role) | `cardRanking` → `galRanking` (`Items = colLockedRanking`), `lblRankCircle`, `btnRankDetails` |
| Next-step → Stage 2 | `cardNext` → `btnContinueStage2` (`Navigate(scrQuestions)`) |
| Home | `btnHome` — **no "Change ranking"** (ranking is locked; see overrides) |

### scrQuestions.pa.yaml — Supporting questions (Stage 2)
*(Workstream 7, 03.07.26: the SAME two branched questions per preference, top **3** preferences, 150-word limit per answer.)*
| Element | Control(s) |
|---|---|
| Back, stage pill, intro | `btnBackReview`, `lblStagePill`, `lblSub` |
| Three sections (top-3 preferences) | `galSections` (`Items = FirstN(colLockedRanking, 3)`); each `cardSection` → `lblSecRank` (ordinal derived from `ThisItem.Rank`), `lblSecRole`, `btnSecDetails` |
| Per-role questions (Q1 "why this [first/second/third] preference" + Q2 "additional skills/experience/qualifications") | nested **`galQuestions`** (`Items = Filter(colAnswers, RoleKey = ThisItem.RoleKey)`) → `lblQ`, **`txtAnswer`** (Classic/TextInput, MultiLine), **`lblWordCount`** (live "n / 150 words") |
| 150-word limit | `txtAnswer.OnChange` patches `Answer` + `WordCount` into `colAnswers`; over-limit → amber border + amber counter; Submit blocked |
| Save draft / Submit | `btnSaveDraft` (always enabled → `varDraftSaved`), `btnSubmit` (enabled when no required answer is blank **and** every answer ≤ 150 words) |
| Draft-saved banner | `bannerDraft` (`Visible = varDraftSaved`) |
| **Submit overlay** | `conSubmitOverlay` → `dlgSubmit` (`btnConfirmSubmit` = **lock Stage 2**) |

### scrCompleted.pa.yaml — Completed (locked)
| Element | Control(s) |
|---|---|
| Green success banner + date | `cardSuccess` → `lblSuccTitle`, `lblSuccDate` (`varStage2Date`) |
| Locked ranking | `cardRanking` → `galRanking` (`colLockedRanking`) |
| Locked answers grouped by role+question | `cardAnswers` → `galAnswerGroups` → nested `galGroupItems`; `lblAnsA` shows entered answer, else `colSampleAnswers` fallback, else "—" |

### scrOverview.pa.yaml — Submissions overview (admin)
| Element | Control(s) |
|---|---|
| Header + admin badge | `btnBackHome`, `lblTitle`, `lblSub` (`CountRows(colOverviewRows)`), `lblAdminView` |
| Table (horizontal-scroll) | `cardTable` (`LayoutOverflowX = Scroll`) → `conColHdr` + **`galRows`** (`Items = colOverviewRows`) |
| Row cells | `cID,cName,cGrade,cArea`, nested `galRowRoles` (ranked roles), `cDate`, `cStage2` pill, `cStatus` pill |
| Row actions | `btnToggle` (`varSelectedOverviewId`), **`btnWithdraw`** (soft: `Patch …{Status:"Withdrawn"}`), `lblNoAction` |
| Expansion | `panelExpand` (`Visible = Not IsBlank(varSelectedOverviewId)`) → `galExpandAnswers` / `lblOutstanding` |

**Confirmation overlays** are containers whose `Visible` is bound to a context
variable (`locShowContinue` on scrForm, `locShowSubmit` on scrQuestions), each
with a `recScrim` (`RGBA(0,43,84,0.55)`), exactly as specified.

---

## 2. Collection → Dataverse repoint map

`App.OnStart` builds in-memory **seed collections** so the app previews with no
connection. After import, add the Dataverse data sources and repoint each
binding below. Every site is also marked `REPOINT` in the YAML comments.

| Seed collection (built in App.OnStart) | Dataverse table | Bound at |
|---|---|---|
| `colRoles` | **Roles** (RoleName, ShortDescription, DetailedDescription, Purpose, Responsibilities, Requirements, GradeContext, Active) | `scrDetail` `lblPurpose`, `galResp`, `galReq`, `lblGradeCtx` |
| `varUser` (literal record) | **People** — replace with `LookUp(People, 'Email/UPN' = User().Email)` | header `lblUserName`/`lblHdrUser`; `scrLanding` welcome card; `scrForm` `galUserFields` |
| `colRanks` (working ranks) | **Eligibility ⋈ Roles** for this person — `Filter(Roles, RoleID in this user's Eligibility set)` | `scrForm` `galRoles` |
| `colPreferences` (written at Stage-1 lock) | **Preferences** (EmployeeID, RoleID, Rank, SubmittedBy, SubmittedOn, Stage1Status) — replace `ClearCollect` with `ForAll(... Patch(Preferences, Defaults(Preferences), {…}))` | `scrForm` `btnConfirmContinue.OnSelect` |
| `colLockedRanking` | **Preferences** for this person, `SortByColumns(…, "Rank")` | `scrReview`/`scrCompleted` `galRanking`; section builders |
| `colRoleQuestions` | **RoleQuestions** (RoleID, QuestionText, Order, Required) — *retained but currently unused; Workstream 7 replaced role-specific questions with two standard ones* | *(no current binding)* |
| `colAnswers` (Stage-2 working set, top 3) | **PreferenceResponses** draft rows (Rank ≤ 3; two standard questions per role, `WordCount` tracked for the 150-word limit) | `scrQuestions` `galQuestions`/`txtAnswer`; `scrCompleted` `galGroupItems` |
| `colPreferenceResponses` (written at Stage-2 lock) | **PreferenceResponses** (PreferenceID, RoleQuestionID, ResponseText, SubmittedOn, Stage2Status) | `scrQuestions` `btnConfirmSubmit.OnSelect` |
| `colSampleAnswers` | *(preview only — delete)* sample fallback text for blank answers | `scrCompleted` `lblAnsA` |
| `colOverviewRows` | **Preferences ⋈ People ⋈ Eligibility ⋈ PreferenceResponses** | `scrOverview` `galRows`, `panelExpand` |
| `colFormErrors` | *(stays a local collection — validation state, not data)* | `scrForm` `panelErrors`, `btnContinue` |

Progress flags `varStage1Submitted` / `varStage2Submitted` are stubbed in
OnStart; after import derive them from the user's **Preferences** /
**PreferenceResponses** rows (e.g. `Set(varStage1Submitted,
CountRows(Filter(Preferences, EmployeeID=varUser.EmpId))>0)`).

**Withdraw** writes `Patch(…, {Status:"Withdrawn"})` against the collection;
repoint to `Patch(Preferences, <row>, {Stage1Status:'Stage1Status'.Withdrawn})`.
It is **soft** — never `Remove()`.

---

## 3. Manual fix-up in Studio

1. **Document settings (can't be expressed in YAML):** Settings → Display →
   set **Scale to fit = OFF**, **Lock aspect ratio = OFF**, **Orientation =
   responsive/Free** so the container layout drives sizing. Confirm
   `App.MaxScreenSize`/`MinScreenWidth` as needed for tablet/phone.
2. **Font — Public Sans.** Canvas font support is limited; Public Sans is not a
   built-in Studio font. After import set a custom font (Theme/JSON or per-label
   `Font`) or fall back to "Open Sans"/"Segoe UI". The dc.html `@font-face`
   declarations do not translate to Canvas.
3. **Admin-group gate.** `varIsAdmin` is stubbed `true` in OnStart. Wire it to a
   real check (e.g. `Office365Groups.ListGroupMembers(<adminGroupId>)` or a
   config table) against `User().Email`. **In-app gating is not security** —
   see #4.
4. **Dataverse row-level security.** Hiding the admin card and filtering rows in
   the app is *not* a security boundary. Enforce table-level security on
   **Preferences/PreferenceResponses** (and the admin "Withdraw" write) with
   Dataverse security roles / row ownership so non-admins cannot read or modify
   other people's rows even via the data source directly.
5. **Control IDs / variants to confirm at import.** The pa.yaml 1P-control enum
   is resolved by Studio. Verify these import as intended and re-pick from the
   modern toolbox if not:
   - `Classic/Button`, `Classic/DropDown`, `Classic/TextInput` (classic controls
     were chosen because they expose `Fill`/`BorderColor`/`Radius*`/`HoverFill`
     directly, matching the mockup). You may prefer modern `Button`/`Dropdown`/
     `TextInput`.
   - `GroupContainer` responsive variants use the Code View names
     `verticalAutoLayoutContainer` / `horizontalAutoLayoutContainer`, and
     `manualLayoutContainer` for the overlay scrims (NOT `AutoLayout`/
     `ManualLayout`, which the paste deserializer rejects). Layout tuning props:
     `LayoutGap`/`LayoutJustifyContent`/`LayoutAlignItems`/`LayoutWrap`/
     `LayoutOverflowY`. `LayoutOverflowX` (overview table) and gallery
     `Variant` strings should be confirmed against your environment via
     **View code** on a control you insert in Studio.
   - `Label` corner-radius props (`RadiusTopLeft`…): if your Label build lacks
     them, the pill/badge `Label`s should be swapped to a `Rectangle` behind a
     transparent `Label`.
6. **Responsive tuning.** Container widths use `Min(Parent.Width-48, 1120)` and
   several fixed column widths (e.g. the overview table, welcome grid). Gallery
   heights are computed as `rows × rowHeight`. Review on tablet/phone and switch
   fixed child widths to `FillPortions`/`LayoutMinWidth` where wrapping is
   preferred. Phone is best-effort.
7. **Variable-height gallery rows.** `scrOverview` renders each person's Stage-2
   answers in **`panelExpand` beneath the table** (toggled by
   `varSelectedOverviewId`) rather than literally inside the row — classic
   galleries can't do per-row variable height. If true inline expansion is
   required, rebuild `galRows` as nested flexible-height containers.
8. **AutoHeight labels.** Long copy uses `AutoHeight = true`; confirm wrapping
   width (`Width = Parent.Width - padding`) so text isn't clipped, and adjust the
   parent gallery `TemplateSize` if content overflows.
9. **Stage-2 questions (Workstream 7, 03.07.26).** Each of the top **3**
   preferences gets the SAME two questions (Q1 "why this [first/second/third]
   preference", Q2 "additional skills/experience/qualifications"), 150-word
   limit each. The word limit is enforced in-app (live counter, amber border,
   Submit gating) — words are counted by collapsing whitespace, so treat it as
   a UX guard, not a hard data constraint; re-validate server-side if needed.
   `colRoleQuestions` is retained but unused should role-specific questions
   ever return.
10. **Header is duplicated per screen.** For maintainability, consider extracting
    `conHeaderBar` + `recGreenStrip` into a **canvas component** after import.

### Behaviour overrides (deliberate — differ from the mockup)
- **Two-stage locking.** Stage 1 "Continue" **submits and locks** the ranking
  (writes Preferences); Stage 2 "Submit" locks the answers (writes
  PreferenceResponses). The mockup's softer continue-dialog copy ("nothing is
  locked until Stage 2") is intentionally replaced. **Single place to revert:**
  `scrForm` → `dlgContinue` → `lblDlgBody.Text` and `btnConfirmContinue.OnSelect`.
- **scrReview has no "Change ranking" button** — consequence of locking Stage 1.
- Dialog **titles and button labels** are kept verbatim from the dc.html; only
  the continue-dialog **body** was changed for the lock.

---

## 4. Import steps

1. **Create the Dataverse tables** from the data model: Roles, People,
   Eligibility, Preferences, RoleQuestions, PreferenceResponses (keys, lookups
   and the `Stage1Status`/`Stage2Status` choice columns as specified).
2. **Bring the source into an app.** These `.pa.yaml` files use the Power
   Platform Git-integration source format:
   - **Git integration:** connect the solution to this repo
     (Solutions → Source control) so `Src/*.pa.yaml` is picked up; or
   - **Power Platform CLI:** place the files as the `Src/` of an unpacked canvas
     app and `pac canvas pack --sources ./Src --msapp Aurora.msapp`, then import
     the `.msapp` (**Apps → Import canvas app**). *(Exact `pac` flags vary by CLI
     version — see learn.microsoft.com "Source code files for canvas apps".)*
3. **Open in Studio** and resolve any controls flagged on import (see #5 above).
4. **Add data sources** and repoint each binding per
   [section 2](#2-collection--dataverse-repoint-map) (collection → table).
   Keep `colFormErrors` as a local collection.
5. **Wire identity & admin:** replace `varUser` with the People lookup and set
   `varIsAdmin` from the real admin group.
6. **Set the font** (Public Sans / fallback) and confirm responsive document
   settings (#1).
7. **Apply Dataverse row-level security** (#4) before any real data is loaded.
8. **Preview.** With the seed collections still present the app runs end-to-end
   offline: Landing → Form (try the seeded duplicate rank 1/1 to see validation)
   → Continue (locks) → Review → Stage 2 → Submit (locks) → Completed; and the
   admin **Submissions Overview** with expand + soft Withdraw.

---

*Source of truth for content, copy, colours and behaviour: the
`Aurora_Role_Preference.dc.html` template + its `data-dc-script` component
(`renderVals`). The Claude Design runtime `support.js` is not part of the app
and was not translated.*
