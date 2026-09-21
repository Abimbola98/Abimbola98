// =============================================================================
// Aurora Preference — integrity queries  (Power Query / M)
// =============================================================================
// These do not feed a chart. They answer "is the report's input sound", and
// they belong on the reconciliation page alongside RoleReconciliation.
//
// AN EMPTY TABLE IS THE GOOD OUTCOME for both of them. Neither corrects
// anything: correcting would hide the fault, and every fault they can find is
// fixable only in Dataverse or the app.
//
// Both read People, Preferences and Eligibility, so paste them AFTER
// 01-sources.m is in place.
//
// WHY THEY EXIST. Preferences, Responses and Alignments all end with
//
//     Real = Table.SelectRows(..., each List.Contains(Buf, [EmployeeID]))
//
// which keeps only rows whose EmployeeID appears in People. That is how test
// accounts are kept out of the numbers, and it is silent by design. Silent is
// right for a tester and wrong for anybody else, and nothing in the report
// distinguished the two until these queries existed.
// =============================================================================


// ---- Query: OrphanedPreferences  (reconciliation page) --------------------
// Every ranked preference row that Preferences throws away for having an
// EmployeeID with no row in People. It re-reads Dataverse independently and
// stops one step short of that filter, which is the only way to see what the
// filter removed.
//
// HOW TO READ THE RESULT:
//   MatchesIfBothTrimmed = TRUE   the id IS a real person and the only
//                                 difference is whitespace. EmployeeID is
//                                 trimmed in Eligibility and in no other query,
//                                 so this is possible. Fix by trimming
//                                 EmployeeID everywhere, not in Dataverse.
//   MatchesIfBothTrimmed = FALSE  the id has no row in People at all. Either a
//                                 test account created straight in Dataverse
//                                 rather than through the app — which is why
//                                 the Grade-based TESTER filter in People never
//                                 catches it, there being no People row to
//                                 carry a grade — or a colleague who ranked
//                                 roles and was then removed from, or never
//                                 added to, People. The second case is serious:
//                                 their preferences are invisible to every
//                                 number in the report.
//   IdLength and IdAsStored tell those apart at a glance. Real ids are six
//   digits; the brackets make a leading, trailing or non-breaking space visible
//   instead of invisible.
//
// AS AT 21/09/2026 this returns 8 rows, all id 67890, all Draft, all written at
// the same second — a hand-typed test account. Expected, and harmless because
// Draft rows are excluded from committed counts anyway. The query stays so that
// the next orphan is noticed rather than absorbed.
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepreferences"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeidrolekey","cr174_rolekey","cr174_rank",
        "cr174_submittedon","cr174_stage1status"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeidrolekey","EmployeeID"}, {"cr174_rolekey","RoleKey"},
        {"cr174_rank","Rank"}, {"cr174_submittedon","SubmittedOn"},
        {"cr174_stage1status","Stage1Status"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"RoleKey", type text}, {"Rank", Int64.Type},
        {"SubmittedOn", type datetime}, {"Stage1Status", type text}
    }),
    Trim   = Table.TransformColumns(Typed, {{"RoleKey", each Text.Trim(_ ?? ""), type text}}),
    Live   = Table.SelectRows(Trim, each [Stage1Status] <> "Withdrawn"),
    // Identical to the Preferences query up to here. The next step is the one
    // Preferences applies; this query keeps what Preferences throws away.
    Ranked = Table.SelectRows(Live, each [Rank] <> null and [Rank] > 0),

    Buf    = List.Buffer(People[EmployeeID]),
    BufT   = List.Buffer(List.Transform(People[EmployeeID], each Text.Trim(_ ?? ""))),
    Gone   = Table.SelectRows(Ranked, each not List.Contains(Buf, [EmployeeID])),

    Show   = Table.AddColumn(Gone, "IdAsStored",
                 each "[" & ([EmployeeID] ?? "(null)") & "]", type text),
    Len    = Table.AddColumn(Show, "IdLength",
                 each Text.Length([EmployeeID] ?? ""), Int64.Type),
    Match  = Table.AddColumn(Len, "MatchesIfBothTrimmed",
                 each List.Contains(BufT, Text.Trim([EmployeeID] ?? "")), type logical),
    Out    = Table.SelectColumns(Match, {
                 "IdAsStored","IdLength","MatchesIfBothTrimmed",
                 "RoleKey","Rank","Stage1Status","SubmittedOn"
             })
in
    Out


// ---- Query: PreferenceIntegrity  (reconciliation page) --------------------
// WHAT IT ANSWERS: did the app ever let somebody rank a role they were not
// eligible for? Every row here is a ranked preference whose (EmployeeID,
// RoleKey) pair does not appear in Eligibility.
//
// It SHOULD be empty. It is the report's check on the app, and it is the only
// place the mismatch becomes visible — Eligibility drives what the app offers,
// but nothing reconciles what was offered against what was saved. A person
// whose Eligibility rows were later corrected keeps the preferences they made
// against the old list, and those rows stay in Dataverse looking valid.
//
// A non-empty result is a Power Apps / Dataverse problem, NOT a Power BI one.
// The fix is on that side: correct Eligibility, then have the person re-rank,
// or delete the stale Preference rows. Do not filter them out here — that would
// hide a person ranking roles they cannot be given.
//
// The what-if page is the one place that does ignore these rows, and for a
// different reason: it simulates the real allocation, and the real allocation
// cannot place someone in a post they were never eligible for. See the
// eligibility guard in 02-whatif-assignment.m.
//
// AS AT 21/09/2026 this returns 5 rows, all one person: ranks 8-12 against five
// Officer roles that were shown to them because another colleague's Eligibility
// had been filed under their id. The Eligibility side has since been corrected;
// the preference rows it produced have not, and cannot be, from the report.
//
// Named columns come from People so the row is readable without a lookup.
let
    Pairs  = Table.AddColumn(Preferences, "PairKey",
                 each ([EmployeeID] ?? "") & "|" & ([RoleKey] ?? ""), type text),
    ElgTbl = Table.AddColumn(Eligibility, "PairKey",
                 each ([EmployeeID] ?? "") & "|" & ([RoleKey] ?? ""), type text),
    ElgBuf = List.Buffer(ElgTbl[PairKey]),
    Bad    = Table.SelectRows(Pairs, each not List.Contains(ElgBuf, [PairKey])),

    // How many roles the person WAS eligible for, so a row reading 0 (nothing
    // in Eligibility at all) is told apart from a row reading 12 (they had a
    // list, and this is not on it — the more suspicious case).
    ElgCount = Table.Group(Eligibility, {"EmployeeID"}, {{"EligibleRoles", each Table.RowCount(_), Int64.Type}}),
    JC     = Table.NestedJoin(Bad, {"EmployeeID"}, ElgCount, {"EmployeeID"}, "E", JoinKind.LeftOuter),
    EC     = Table.ExpandTableColumn(JC, "E", {"EligibleRoles"}, {"EligibleRoles"}),
    Count0 = Table.TransformColumns(EC, {{"EligibleRoles", each _ ?? 0, Int64.Type}}),

    JN     = Table.NestedJoin(Count0, {"EmployeeID"}, People, {"EmployeeID"}, "P", JoinKind.LeftOuter),
    EN     = Table.ExpandTableColumn(JN, "P", {"Name","Grade","Area"}, {"Name","Grade","Area"}),

    Out    = Table.SelectColumns(EN, {
                 "EmployeeID","Name","Grade","Area","RoleKey","Rank",
                 "EligibleRoles","Stage1Status","SubmittedOn"
             }),
    Sorted = Table.Sort(Out, {{"EmployeeID", Order.Ascending}, {"Rank", Order.Ascending}})
in
    Sorted


// ---- Query: DiagPersonTrace  (TEMPORARY — delete when answered) -----------
// WHAT IT ANSWERS: "this person exists in Dataverse, so why are they not in the
// report?" It follows a handful of ids through every table in the model in
// order, and returns a row count per table per person. The first table showing
// 0 is where they drop out, and that tells you which query to look at.
//
// It does NOT re-read Dataverse. It reads the loaded queries, which is the
// point — it measures the model as built, not the source.
//
// HOW TO READ IT, stage by stage:
//   1 People            0 = they are not a colleague as far as the model is
//                       concerned, and EVERYTHING downstream is filtered out by
//                       the List.Contains(People[EmployeeID]) step. Fix in
//                       Dataverse.
//   2 Eligibility       0 = HasOptions is false for them, so they are outside
//                       the in-scope headcount and every "offered to selection"
//                       measure ignores them.
//   3 Preferences       0 = they have not ranked, or their rows were dropped at
//                       stage 1. Non-zero is the count of roles they ranked.
//   4 PreferenceWide    0 with stage 3 non-zero = they ranked, but not ranks
//                       1-3, so the top-three columns have nothing to show.
//   5 Responses         0 = NO STAGE 2 FREE TEXT EXISTS FOR THEM. This is the
//                       usual answer for a manually entered form: the rankings
//                       were typed into the Preferences table and the written
//                       justifications were never typed into the Responses
//                       table. The person is then correct on every Stage 1
//                       visual and absent from every Stage 2 one, which looks
//                       like a report fault and is a data-entry gap.
//   6 ResponseThemes    0 with stage 5 non-zero = their text matched no theme
//                       keyword. Expected sometimes; they still appear under
//                       "(no theme matched)".
//   7 PreferenceDetail  the Excel export. Should equal stage 3.
//   8 WhatIfAssignment  0 with stage 3 non-zero should be impossible.
//   9 Alignments        0 = no Phase 2 decision recorded yet. Expected for now.
//
// Put the ids you are chasing in the Ids list. Quoted -- EmployeeID is text.
// The placeholders below are NOT real ids. This repository is public and holds
// no employee identifiers; replace them in Desktop and do not commit the result.
let
    Ids   = {"000001","000002","000003"},

    Probe = (label as text, tbl as table) as list =>
        List.Transform(Ids, (i) =>
            [ Stage      = label,
              EmployeeID = i,
              Rows       = Table.RowCount(
                               Table.SelectRows(tbl, (r) => r[EmployeeID] = i)) ]),

    All   = Probe("1 People",           People)
          & Probe("2 Eligibility",      Eligibility)
          & Probe("3 Preferences",      Preferences)
          & Probe("4 PreferenceWide",   PreferenceWide)
          & Probe("5 Responses",        Responses)
          & Probe("6 ResponseThemes",   ResponseThemes)
          & Probe("7 PreferenceDetail", PreferenceDetail)
          & Probe("8 WhatIfAssignment", WhatIfAssignment)
          & Probe("9 Alignments",       Alignments),

    T     = Table.FromRecords(All,
                type table [Stage = text, EmployeeID = text, Rows = Int64.Type]),
    P     = Table.Pivot(T, Ids, "EmployeeID", "Rows", List.Sum),
    S     = Table.Sort(P, {{"Stage", Order.Ascending}})
in
    S


// ---- Query: DiagTableShape  (TEMPORARY — delete when answered) ------------
// WHAT IT ANSWERS: "is this table the shape it claims to be?"
//
// Several queries in this model promise one row per person. PreferenceWide says
// so in its own header; WhatIfAssignment ends in a Table.Group on EmployeeID, so
// it cannot be anything else. If RowsPerID is not exactly 1 for those two, a
// join has multiplied rows somewhere downstream of the group, and EVERY count
// over that table is inflated by the same factor.
//
// This is the failure that does not announce itself: the rows are real, the
// values in them are correct, and there are simply more of them than there are
// people. A card counting people reads a multiple of the truth and looks
// entirely plausible.
//
// EXPECTED:
//   People            RowsPerID = 1
//   PreferenceWide    RowsPerID = 1     <- one row per respondent
//   WhatIfAssignment  RowsPerID = 1     <- grouped on EmployeeID
//   Preferences       RowsPerID > 1     <- one row per ranked role, correct
//   PreferenceDetail  RowsPerID > 1     <- same, it is the export
//   Eligibility       RowsPerID > 1     <- one row per offered role, correct
let
    Count = (label as text, tbl as table) as record =>
        let
            r = Table.RowCount(tbl),
            d = List.Count(List.Distinct(Table.Column(tbl, "EmployeeID")))
        in
            [ Query = label, Rows = r, DistinctIDs = d,
              RowsPerID = if d = 0 then 0 else Number.Round(r / d, 2) ],

    T = Table.FromRecords({
            Count("People",           People),
            Count("Eligibility",      Eligibility),
            Count("Preferences",      Preferences),
            Count("PreferenceWide",   PreferenceWide),
            Count("PreferenceDetail", PreferenceDetail),
            Count("WhatIfAssignment", WhatIfAssignment),
            Count("Responses",        Responses)
        },
        type table [Query = text, Rows = Int64.Type,
                    DistinctIDs = Int64.Type, RowsPerID = Number.Type])
in
    T


// ---- Query: DiagDimRoleDuplicates  (TEMPORARY — delete when answered) -----
// WHAT IT ANSWERS: does DimRole hold the same RoleKey more than once?
//
// DimRole is a FULL OUTER merge of the app's role list and the capacity sheet.
// If either side carries a key twice -- a role split across two capacity rows,
// say -- the merge emits both, and DimRole stops being a dimension.
//
// PreferenceWide then joins DimRole THREE times, once per top-three key, to
// resolve names. Table.ExpandTableColumn multiplies: a key with two matches
// turns one respondent into two rows, and two such keys turn them into four.
// WhatIfAssignment joins PreferenceWide and inherits whatever came out.
//
// This should return ZERO ROWS -- and in the version of DimRole in this repo it
// cannot do otherwise, because that query ends with
//
//     Dedup = Table.Distinct(Fam, {"RoleKey"})
//
// So a non-empty result here means something more useful than "there are
// duplicates": it means the DimRole loaded in Desktop is NOT the version in
// this repo and is missing that final step. Re-paste DimRole from
// 01-sources.m before looking any further, because every page uses it.
//
// If it IS deduplicated and PreferenceWide still has more than one row per
// person, the multiplication is not coming from these joins and the Table.Group
// above them is the thing to look at.
//
// It is worth knowing that a duplicate here does NOT necessarily break the
// relationships. Power BI refuses a one-to-many on a non-unique key at the
// moment you create it, but a duplicate introduced later silently degrades what
// is already built rather than failing the refresh.
let
    Grouped = Table.Group(DimRole, {"RoleKey"}, {
                  {"Rows", each Table.RowCount(_), Int64.Type},
                  {"Names", each Text.Combine(
                                List.Distinct(List.Transform(_[RoleName], each _ ?? "(null)")),
                                " | "), type text},
                  {"Posts", each Text.Combine(
                                List.Transform(_[Posts], each Text.From(_ ?? 0)), " | "), type text}
              }),
    Dupes   = Table.SelectRows(Grouped, each [Rows] > 1)
in
    Dupes


// ---- Query: GradeReconciliation  (reconciliation page) ---------------------
// The live answer to the question BUILD.md section 10 asks of the workbooks:
// per grade, how many people are in scope, how many distinct roles they are
// offered between them, how many posts those roles carry, and how many
// eligibility rows that is.
//
// Compare it line by line with the same figures computed from the Options and
// capacity workbooks. They must agree. Where they do not, Dataverse Eligibility
// and Claire's final list have diverged, and the report is reporting Dataverse.
//
// WHY THIS IS A QUERY AND NOT A VISUAL. A visual over DimRole cannot be filtered
// by a People slicer, so a grade-by-grade role count assembled on a page depends
// on the People-to-Eligibility relationship being present and correct. This
// query joins the tables itself and does not, so it says what the DATA holds
// whatever the model is doing. If this disagrees with the same breakdown on a
// page, the fault is in the model, not the data.
//
// NOTE ON POSTS. Posts are summed over DISTINCT roles, not over eligibility
// rows. Summing the row-level Posts column would multiply each role's posts by
// the number of people offered it and produce a number several times the size
// of the establishment.
let
    // HasOptions is what marks a colleague as covered by the process. People
    // without it are colleagues in the same teams who are not being moved.
    Scope   = Table.SelectRows(People, each [HasOptions] = true),
    Grades  = Table.SelectColumns(Scope, {"EmployeeID","Grade"}),

    // Inner join: an eligibility row whose person is out of scope, or absent
    // from People entirely, is not counted toward any grade. If that drops
    // rows, OrphanedPreferences and the People row count will say so.
    JE      = Table.NestedJoin(Eligibility, {"EmployeeID"}, Grades, {"EmployeeID"}, "P", JoinKind.Inner),
    EE      = Table.ExpandTableColumn(JE, "P", {"Grade"}, {"Grade"}),

    JD      = Table.NestedJoin(EE, {"RoleKey"}, DimRole, {"RoleKey"}, "D", JoinKind.LeftOuter),
    ED      = Table.ExpandTableColumn(JD, "D", {"Posts"}, {"Posts"}),

    Grp     = Table.Group(ED, {"Grade"}, {
                  {"People",
                      each List.Count(List.Distinct(_[EmployeeID])), Int64.Type},
                  {"DistinctRoles",
                      each List.Count(List.Distinct(_[RoleKey])), Int64.Type},
                  {"Posts",
                      each List.Sum(
                          Table.Group(_, {"RoleKey"}, {
                              {"P", each List.Max([Posts]) ?? 0, Int64.Type}
                          })[P]) ?? 0, Int64.Type},
                  {"EligibilityRows", each Table.RowCount(_), Int64.Type}
              }),
    Ratio   = Table.AddColumn(Grp, "PeoplePerPost",
                  each if [Posts] = 0 then null
                       else Number.Round([People] / [Posts], 2), type number),
    Sorted  = Table.Sort(Ratio, {{"Grade", Order.Ascending}})
in
    Sorted
