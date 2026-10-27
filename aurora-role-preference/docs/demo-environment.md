# Demo copy of the app, with fictional data

For showing the app to people who must not see the real data. Everything they
see comes from invented people; nothing is read from SS-Project-Aurora.

## The one rule: a separate environment

A copy made with **Save as** in SS-Project-Aurora still reads SS-Project-Aurora's
tables — the real data. Dataverse tables belong to the environment, not to the
app, so a copy cannot have different data while it sits in the same environment.

The demo copy therefore lives in **its own environment with its own tables**,
filled from the fictional files. Never import the demo files into
SS-Project-Aurora, and never add the demo reset button to the live app.

## 1. Make a demo environment

Power Platform admin centre → **Environments → New**. Type **Developer** (or
Sandbox), with a Dataverse database. If you cannot create one, ask the Power
Platform admins for one.

## 2. Move the tables and the app across — structure only, no data

In **SS-Project-Aurora**, make.powerapps.com → **Solutions → New solution**
(any name, e.g. *Aurora demo*, any publisher), then:

1. **Add existing → Table** → the six RolePreference tables: Roles, People,
   Eligibilities, Preferences, PreferenceResponses, Alignments. Include all
   their components. A solution carries table *structure*, never rows.
2. **Add existing → App → Canvas app → Outside Dataverse** → your duplicated app.
3. **Export → Unmanaged** and download the .zip.

In the **demo environment**: **Solutions → Import solution** → the .zip → create
an Office 365 Outlook connection when asked → **Import**.

Why this way: the tables arrive with exactly the names (`cr8e9_…`) the app was
built against, so it binds with no formula changes. Creating the tables from
spreadsheets instead gives them the demo environment's own prefix, and the app
cannot find them — the same failure as the move to SS-Project-Aurora.

## 3. Load the fictional data

For each table: **Tables → the table → Import → Import data from Excel**, in this
order, waiting for each import to finish and checking its row count first:

| File | Rows |
|---|---|
| `RolePreference_Roles_DEMO.xlsx` | 16 |
| `RolePreference_People_DEMO.xlsx` | 40 |
| `RolePreference_Eligibilities_DEMO.xlsx` | 181 |
| `RolePreference_Preferences_DEMO.xlsx` | 156 |
| `RolePreference_PreferenceResponses_DEMO.xlsx` | 210 |
| `RolePreference_Alignments_DEMO.xlsx` | 40 |

The column limits come across from SS-Project-Aurora. Check **RejectComments**
and **RejectReasons** on Alignments are 4000 characters before the demo — a
presenter's own rejection is written there live. If an import rejects a row for
length, raise that column's **Maximum character count** and import the failed
rows again; the import's error list names them.

## 4. Two edits in the demo copy only

Open the app in the demo environment → **Edit**:

1. **Confirmation emails go to the presenter only.** In `btnEmailAccept.OnSelect`
   (scrAlignment) and `btnEmailReject.OnSelect` (scrRejection), replace
   `"aurora@environment-agency.gov.uk" & If(IsBlank(varAlignLmEmail), "", ";" & varAlignLmEmail)`
   with `varUserEmail`. Otherwise every demo response emails the Aurora mailbox
   and whichever line manager was typed in. This way the email arrives in your
   own inbox, which is worth showing.
2. **A reset button.** On scrLanding, **Insert → Button**: Text `"Reset demo"`,
   Visible `varIsAdmin`, OnSelect = `paste/test-app/demo-reset.powerfx` (the `_1`
   version, like your other pastes). It clears your own form, answers and
   response so the next run starts fresh.

**Save → Publish.** If formulas show errors after the move, refresh each table
in the Data pane (hazard 17 in HANDOFF.md).

## 5. Who can sign in

Everyone in the files is invented — names, `example.com` addresses (a domain
reserved for examples, so no mail can reach anyone), employee numbers from
900101 — except the **presenters**, who must be in People under their real
sign-in address or the app cannot find them. Presenters are admins, may rank
five roles, have **not** filled in the form, and have an aligned role waiting.

Presenters' details are real staff data, so they are not in this repository
(it is public). They are passed to the generator from a local CSV; see
*Regenerating* below. To add a presenter by hand instead: one People row
(IsAdmin `Yes`), Eligibilities rows for a few roles, and one Alignments row.

Anyone else presenting needs the demo environment too: add them as a user with
a security role that can read and write the six tables (System Administrator is
simplest in a demo environment), and share the app with them. Do not give the
audience access to SS-Project-Aurora.

## 6. What the data shows

- **Admin Overview** — 40 people with an aligned role: 22 accepted, 5 rejected
  (with reasons and comments), 13 not yet responded, including one saved draft
  rejection and the presenters.
- **Submissions** — ranked preferences and supporting answers for everyone who
  completed the form, two people part-way through.
- **Line-manager view** — the first presenter is named as line manager for five
  fictional staff. Set your own IsAdmin to `No` in People and reopen the app to
  see only those five; set it back afterwards.

## 7. A walkthrough

1. **Landing** — your name and grade, and the three cards.
2. **My Preference Form** — rank the five roles, open one to show its details,
   answer the questions for your top three, review, submit.
3. **Role Alignment** — your top three and answers, then the aligned role. Type
   a colleague's email as line manager (the app refuses your own), tick the box,
   then **Accept** — or **Reject**, tick a reason, write a few lines, save a
   draft, submit. The confirmation email arrives in your inbox.
4. **Admin Overview** — tabs, area filter, search; press **Refresh data** and
   your own response appears. **View submissions & supporting answers** →
   **View answers** on anyone.
5. **Reset demo**, then F5, ready for the next run.

## Regenerating the data

```
python3 tools/make_demo_data.py --out <folder> --presenters <presenters.csv>
```

`presenters.csv` has the columns `Name,EmployeeID,Email` (plus optional
`Grade,Area,Team`). Keep it, and the generated files, out of this repository.
The output is the same every time for the same `--seed`.
