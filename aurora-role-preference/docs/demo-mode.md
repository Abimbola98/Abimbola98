# Demo mode: a copy of the app that runs on fictional data

For showing the app to people who must not see the real data, without a new
environment. The copy keeps every screen and formula of the live app, but each
Dataverse table is swapped for an in-memory collection of invented data, so it
reads and writes **no real data** — it can sit next to the live app in
SS-Project-Aurora. Nothing it does is saved anywhere: refresh the browser and
it starts again from scratch.

## Why OnStart alone is not enough

OnStart is where the app *loads* its data, but seven screens also talk to the
tables directly:

| Screen | What it does with the tables |
|---|---|
| scrLanding | shows the Admin Overview card to line managers (reads Alignments) |
| scrForm, scrQuestions | save the ranking and the answers |
| scrAlignment, scrRejection | save Accept / Reject |
| scrOverview, scrSubmissions | build the admin pages straight from the tables; delete submissions |

With only OnStart changed, the admin pages would still show the **real staff
list and answers**, and a demo run would **save into the real tables**. Every
one of those formulas is swapped in the demo files.

## Set it up (in your duplicate — never in the live app)

The files are in `paste/demo-app/`. Copy each from GitHub with **Copy raw
file**, as with every other paste.

1. **Rename the copy**, e.g. *Aurora — DEMO*, so nobody opens the wrong one.
2. **App → OnStart**: replace it with `App_OnStart.demo.powerfx`.
3. **Seven screens** — scrLanding, scrForm, scrQuestions, scrAlignment,
   scrRejection, scrOverview, scrSubmissions. For each: in the Tree view delete
   the controls under the screen, select the screen, and paste the matching
   `<screen>.controls.yaml` from `paste/demo-app/` (right-click → **Paste
   code**). The other four screens name no table and stay as they are.
4. **Two OnVisible formulas**: scrOverview → OnVisible =
   `scrOverview_OnVisible.powerfx`; scrSubmissions → OnVisible =
   `scrSubmissions_OnVisible.powerfx` (both from `paste/demo-app/`).
5. **Remove every RolePreference table from the copy's Data pane** — all of
   them, including the `_1` ones. This is the safety net: anything still
   pointing at a table now shows an error instead of quietly reading real data.
   If something goes red (an old test button, say), delete it; **App checker**
   lists them all.
6. **Run OnStart**, then **Save** and **Publish**. Keep **Office 365 Outlook**
   in the Data pane: the confirmation email is part of the demo.

## Using it

- **Whoever opens it is the presenter**: added as an admin, with five roles to
  rank, the form not yet filled in, and an aligned role waiting for a response.
  Nobody's details need adding, and no real person is in the data.
- **The fictional data**: 20 staff on `example.com` addresses (a domain reserved
  for examples). The Admin Overview shows 21 people with an aligned role —
  10 accepted, 3 rejected with reasons and comments, and 8 not yet responded,
  including you and one saved draft rejection. Submissions shows their
  rankings and supporting answers.
- **The confirmation email goes to you only** — the demo files take out the
  Aurora mailbox and the line manager. On the alignment page, type any
  address that isn't your own as line manager (e.g. `jordan.ellis@example.com`);
  nothing is sent to it.
- **Line-manager view**: at the top of the OnStart, change
  `Set(varDemoPresenterIsAdmin, true)` to `false` and **Run OnStart**. You then
  see only the five fictional staff who named you as their line manager.
- **Start again**: refresh the browser page (in Studio, **Run OnStart**). Your
  ranking, answers and response are gone and the data is back as it was.

### A walkthrough

1. **Landing** — your name and grade, and the three cards.
2. **My Preference Form** — rank the five roles, open one to show its details,
   answer the questions for your top three, review, submit.
3. **Role Alignment** — your top three and answers, then the aligned role. Type
   a line manager address, tick the box, then **Accept** — or **Reject**, tick
   a reason, write a few lines, save a draft, submit. The email arrives in your
   inbox.
4. **Admin Overview** — tabs, area filter, search; **Refresh data** and your own
   response is there. **View submissions & supporting answers** → **View
   answers** on anyone.
5. Refresh the browser, ready for the next run.

## Who can open it

The copy lives in SS-Project-Aurora, so only people with access to that
environment can open it — fine for presenting on a shared screen. If the
audience needs to click through it on their own devices, use a separate demo
environment instead (`demo-environment.md`); do not add them to
SS-Project-Aurora.

## Keeping it in step with the live app

The demo files are generated from the live paste files by
`tools/gen_paste.py`, with the fictional data from `tools/make_demo_data.py`.
After a change to the live app, regenerate and re-paste whichever demo files
changed. `tools/scan_paste.py` (rule 13) fails if any demo file still names a
RolePreference table, calls `Refresh()`, or copies the Aurora mailbox into an
email.
