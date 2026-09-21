// =============================================================================
// Aurora Preference — diagnostics  (Power Query / M)
// =============================================================================
// Queries that answer "why is this number wrong", not queries that feed a
// visual. Two kinds live here:
//
//   Diag*   TEMPORARY. Paste, read the answer, then right-click > Delete.
//           They re-read Dataverse independently so they can see rows that the
//           loaded queries have already filtered away. Leaving one loaded adds
//           a table to the model that nothing uses.
//
//   everything else  PERMANENT, and belongs on the reconciliation page. These
//           surface data problems the report would otherwise hide. An empty
//           table here is the good outcome.
//
// These read People, Preferences and Eligibility, so paste them AFTER
// 01-sources.m is in place.
// =============================================================================


// ---- Query: DiagDroppedPreferences  (TEMPORARY — delete when answered) -----
// WHAT IT ANSWERS: Preferences goes from 444 rows at the Ranked step to 436 at
// Real. Eight rows are discarded by
//
//     Real = Table.SelectRows(Ranked, each List.Contains(Buf, [EmployeeID]))
//
// which drops any row whose EmployeeID is not in People. That filter exists to
// remove test accounts, and it does so silently — which is correct for a
// tester and wrong for anybody else.
//
// HOW TO READ THE RESULT:
//   MatchesIfBothTrimmed = TRUE   the id IS a real person; the only difference
//                                 is whitespace. People and Preferences do not
//                                 trim EmployeeID, Eligibility does. Fix by
//                                 trimming EmployeeID in every query, not by
//                                 editing the row in Dataverse.
//   MatchesIfBothTrimmed = FALSE  the id genuinely has no row in People. Either
//                                 a tester (expected, ignore) or somebody who
//                                 ranked roles and was then removed from, or
//                                 never added to, People (a real problem — their
//                                 preferences are invisible to the report).
//   IdAsStored is wrapped in square brackets so a trailing space, a leading
//   space or a non-breaking space is visible instead of invisible.
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


// ---- Query: PreferenceIntegrity  (PERMANENT — reconciliation page) ---------
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
