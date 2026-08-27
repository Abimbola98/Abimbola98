# PAB-6118 — the alignment export, and getting it back in

**Ticket:** <https://fcrmreporting.atlassian.net/browse/PAB-6118>

Two halves of one loop:

1. **Out** — export everyone's preference data as a formatted spreadsheet with
   two blank columns, **Assigned Role** and **Assigned Role Reason (150 words
   max)**.
2. **Back in** — import Kate/Claire's answers into
   `RolePreference Alignments`, which is what switches the **Role Alignment**
   card on for each person.

Template: [`../export/PAB-6118_Aurora_Export_Template.xlsx`](../export/PAB-6118_Aurora_Export_Template.xlsx)
— three sheets: *Read me*, *Aurora Export* (the 20 columns in the ticket's
order, the two editable ones shaded amber), and *Checks* (a live word count on
every reason, flagging anything over 150).

---

## 1. The 20 columns

| # | Heading | Comes from |
|---|---|---|
| 1–2 | First Name · Last Name | split off `People.Name` |
| 3 | Email Address | `People.Email` |
| 4 | Current Role | **HR sheet** — not in Dataverse |
| 5–6 | Area · Team | `People.Area` / `People.Team` |
| 7 | Line Manager | **HR sheet** — not in Dataverse |
| 8–9 | Grade · Employee Number | `People.Grade` / `People.EmployeeID` |
| 10, 13, 16 | Preference 1 / 2 / 3 | `Preferences.RoleKey` at Rank 1/2/3, resolved to `Roles.RoleName` |
| 11–12, 14–15, 17–18 | the six supporting answers | `PreferenceResponses.ResponseText` at `QIndex` 0 and 1 |
| 19 | Assigned Role | **left blank for Kate/Claire** |
| 20 | Assigned Role Reason | **left blank for Kate/Claire** |

**Current Role and Line Manager are the only awkward ones.** The People table
was built from the HR sheet but only carried Name / EmployeeID / Email / Grade
/ Area / Team, because nothing in Stage 1 or 2 needed more. Either:

- **VLOOKUP them in the spreadsheet** on Employee Number, from the same HR
  sheet used to build the app — nothing to change, and fine for a one-off; or
- **add `CurrentRole` and `LineManager` Text columns to
  `RolePreference People`**, import them once from the HR sheet, and swap the
  two `""` placeholders in
  [`../paste/export-alignment-columns.powerfx`](../paste/export-alignment-columns.powerfx)
  for `p.CurrentRole` and `p.LineManager`. Worth doing if the export will be
  run more than once.

## 2. Producing the export

**Easiest — straight out of Dataverse.** make.powerapps.com → **Tables** →
each of *People*, *Preferences*, *PreferenceResponses*, *Roles* → **Export
data**. Join them in Excel on `EmployeeID` / `RoleKey`, then paste into the
template. No app change at all.

**In-app —** paste
[`../paste/export-alignment-columns.powerfx`](../paste/export-alignment-columns.powerfx)
onto a temporary admin button. It builds `colExportRows` with the columns
already in the ticket's order (plus the three alignment-response columns, which
are free once the table exists). Read it out of **View → Collections**, or put
a Power Automate *Create CSV table* behind the same button if this is going to
be run repeatedly.

Either way the last step is the same: paste into the template so the headings,
column widths and word-count checks come with it.

## 3. Filling it in

That is Kate and Claire's part. The *Read me* sheet says it in the workbook,
but the two things that actually matter to the app are:

- **Assigned Role must match a role name in `RolePreference Roles` exactly**,
  or the import cannot resolve a `RoleKey`. The app still shows the typed name
  if it cannot — but a matched key is what lets a future report group by role.
- **No semicolons as separators inside a reason.** Rejection reasons are stored
  `;`-separated in the same table, and a stray one in the wrong column makes an
  export awkward to read.

Deadline for the 150-word reasonings was **21 September** — confirm with Kate
and Claire before assuming it holds.

## 4. Importing the answers

Create one `RolePreference Alignments` row per person (schema in
[`dataverse-setup.md`](dataverse-setup.md)):

| Spreadsheet column | Alignments column |
|---|---|
| Employee Number | `EmployeeID` |
| Assigned Role | `AssignedRoleName` |
| Assigned Role Reason | `AssignedReason` |
| *(look up the role's key)* | `AssignedRoleKey` *(optional)* |

Leave `Decision`, `RejectReasons`, `RejectComments`, `Status`, `DecisionOn` and
`DecisionBy` **empty** — those are the app's to write.

make.powerapps.com → **Tables → RolePreference Alignments → Import → Import
data from Excel** and map the four columns. Import only the rows that have a
role in column S; a row with a blank `AssignedRoleName` leaves that person's
Role Alignment card shut, which is the correct behaviour but is confusing if it
was not meant.

**Until the real data arrives**, run
[`../paste/seed-alignments-dummy.powerfx`](../paste/seed-alignments-dummy.powerfx)
once from a temporary button. It proposes each person their own rank-1 role
with a placeholder reasoning, so the screens can be demoed and tested. Every
placeholder reasoning contains the word *Placeholder* — search for it to prove
none survived into the live data.

## 5. What the app does with it

The moment a person has an Alignments row with a role name:

- the **Role Alignment** card on the homepage opens, badged *ACTION REQUIRED*;
- **Open form** takes them to `scrAlignment` — their own top three with the
  supporting answers behind a *View answers* panel, then the aligned role and
  the reasoning, then **Accept role** / **Reject role**;
- accepting writes `Decision = "Accepted"`, `Status = "Submitted"` and locks;
- rejecting collects reasons and up to 150 words on `scrRejection`, which can
  be saved as a draft as often as they like before submitting;
- once submitted, the card reads *COMPLETED* and only the locked view is
  reachable.
