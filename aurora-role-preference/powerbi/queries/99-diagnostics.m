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
