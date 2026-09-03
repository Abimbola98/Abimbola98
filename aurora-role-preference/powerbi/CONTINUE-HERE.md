# Power BI — prompt for a fresh chat

Power BI development runs in its **own conversation**, separate from Power Apps
work, so the two streams stop colliding on one branch. Paste everything in the
block below into a new chat to pick it up.

---

```
Continue Power BI development for the Aurora Role Preference project.

REPO / WHERE THE WORK IS
- Repo: Abimbola98/Abimbola98
- Branch: claude/power-apps-canvas-yaml-dbqoyt (open PR #10 against main)
- All Power BI work lives in: aurora-role-preference/powerbi/
- Read aurora-role-preference/powerbi/README.md FIRST. It is the build spec:
  files, build order, data model, page-by-page layout, and the data problems.

SCOPE BOUNDARY — IMPORTANT
This chat is Power BI ONLY. The Power Apps canvas app is being developed in a
separate conversation and I do not want the two confused. Do not edit anything
under Src/, paste/, tools/ or docs/ unless I explicitly ask. If a Power BI
problem turns out to need an app-side or Dataverse-side change, tell me and I
will take it to the other chat — do not fix it here.

Because two sessions already collided on this branch and needed a rebase, start
by creating a branch for this stream (e.g. claude/aurora-powerbi) off the
current branch, and push Power BI work there. Confirm with me before your first
push.

WHAT THE DASHBOARD IS
Reporting over the Aurora preference process. Jira PAB-6119 is the respondent
table page. Wireframes exist for three pages: process summary, over/under-
subscribed heatmap, and a what-if page modelling who gets their 1st/2nd/3rd
choice. Plus pages for alignment accept/challenge and free-text themes.

ARCHITECTURE — two sources joined on RoleKey
- Dataverse (live app data): People, Roles, Preferences, Responses, Alignments.
  Refreshes with no gateway.
- CSV (powerbi/data/roles_capacity.csv): post counts only, from the
  Preference_Process_roles_available.xlsx the business supplied. Nothing else
  supplies these.
- AppRoles + CapacityCsv are staging queries (Disable Load). A FULL OUTER merge
  on RoleKey produces DimRole, the single role dimension everything hangs off.
  DimRole[JoinStatus] classifies every role: Matched / Matched-but-zero-posts /
  Capacity-sheet-only-no-key / Capacity-sheet-only-missing-from-app /
  App-only-no-post-count. There is a reconciliation page whose only job is to
  surface these — a two-source model fails silently otherwise.

WHAT EXISTS
- powerbi/queries/01-sources.m — every source query + DimRole merge + reconciliation
- powerbi/queries/02-whatif-assignment.m — capacitated greedy assignment in M
  (sequential capacity decrement, so not DAX), with a seeded deterministic
  shuffle from a hash of EmployeeID so a given WhatIfSeed reproduces its run
- powerbi/queries/03-textanalysis.m — word frequency, stopwords, theme tagging
- powerbi/measures.dax — all measures, grouped by page
- powerbi/data/roles_capacity.csv — cleaned capacity, data issues as columns

WHAT DOES NOT EXIST — and the main constraint
There is NO .pbix. It is a proprietary binary only Power BI Desktop writes, so
it cannot be produced from a coding session. Everything above is what goes into
one. Assume I am assembling it in Desktop and that your job is to produce
correct, pasteable M and DAX plus precise build instructions — not to claim you
have built a report. If you are ever unsure whether something can be delivered
as a file, say so rather than implying otherwise.

None of the M or DAX has been executed. It is written against documented Power
Query / DAX behaviour and reviewed, but not run in Desktop. Treat first-run
errors as expected and iterate with me; do not assume it works.

KNOWN DATA PROBLEMS (business decisions, not code bugs)
- 66 roles, 80 posts, ~111 people: oversubscribed ~1.4:1 before preferences.
- 3 capacity rows have "?" instead of a RoleKey (given synthetic NOKEY-nn keys
  so they stay countable without breaking the 1-to-many relationship).
- R16 has 0 posts — rankable in the app, never assignable.
- R08 is in the capacity sheet but was missing from the app's Roles table; this
  is the "[missing role: R08]" a tester hit.
- Two sheet annotations ("4 roles available in total", "3 roles available in
  total") contradict their own per-row counts. The model uses the per-row
  column, so Total Posts may be overstated by 4. Unresolved.

SENTIMENT ANALYSIS — deliberate decision, do not silently reverse
The brief asks for ML sentiment. Power BI's built-in scoring needs Premium/PPU
and sends text to Azure, which is a data-protection question for OFFICIAL
SENSITIVE free text about people's jobs. What is shipped instead is
deterministic theme tagging + word frequency: no licence, nothing leaves the
tenant, auditable. The reasoning is at the foot of 03-textanalysis.m. If I ask
for real sentiment, raise the IG question first.

SECURITY
The app's admin gate is varIsAdmin in Power Fx. That is not security and does
not carry into Power BI. This report contains every respondent's name, grade,
area and free text. Restrict the workspace; do not assume app-side gating
protects it.

WHAT I WANT NEXT
[replace this line with whatever you want done first]
```
