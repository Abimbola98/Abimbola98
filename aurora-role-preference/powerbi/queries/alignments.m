// =============================================================================
// Alignments query on its own - paste this WHOLE file into ONE query.
// Transform data > select the Alignments query > Advanced Editor >
// Ctrl+A > Delete > paste > Done.
// Same text as the Alignments block in 01-sources.m; keep the two in step.
// Do not paste 01-sources.m whole into one query: it holds many queries, and
// the editor stops at the second one with "Token Eof expected".
// =============================================================================
// ---- Query: Alignments  (Phase 2 — accept / challenge) ---------------------
// Only exists once the Alignments table has been created in Dataverse. If it
// has not, right-click this query and Disable Load rather than deleting it —
// the pages that use it show blank instead of erroring.
//
// FINDS THE TABLE AND ITS COLUMNS BY THE PART AFTER THE PREFIX, so the same
// text works in the first environment (cr174_) and in SS-Project-Aurora
// (cr8e9_) without editing. A column the table does not have comes through
// blank instead of failing the refresh: LineManagerEmail and DecisionBy were
// added late and older copies of the table lack them.
let
    Source  = CommonDataService.Database(EnvUrl),
    TblRow  = Table.SelectRows(Source, each [Schema] = "dbo"
                  and (Text.EndsWith([Item], "_rolepreferencealignment")
                       or Text.EndsWith([Item], "_rolepreferencealignments"))),
    Tbl     = TblRow{0}[Data],
    Names   = Table.ColumnNames(Tbl),
    // Model name -> the logical-name endings it may have, best match first.
    // The model keeps "Status" because the page 5 measures read
    // Alignments[Status]; in Dataverse the column is AlignmentStatus (a column
    // called Status collides with the built-in statecode display name).
    Map     = {
        {"EmployeeID",       {"employeeid"}},
        {"AssignedRoleKey",  {"assignedrolekey"}},
        {"AssignedRoleName", {"assignedrolename"}},
        {"AssignedReason",   {"assignedreason"}},
        {"Decision",         {"decision"}},
        {"RejectReasons",    {"rejectreasons"}},
        {"RejectComments",   {"rejectcomments"}},
        {"Status",           {"alignmentstatus", "status"}},
        {"DecisionOn",       {"decisionon"}},
        {"DecisionBy",       {"decisionby"}},
        {"LineManagerEmail", {"linemanageremail"}}
    },
    Logical = (endings as list) as nullable text =>
                  List.First(List.RemoveNulls(List.Transform(endings, (e) =>
                      List.First(List.Select(Names, (n) => Text.EndsWith(Text.Lower(n), "_" & e)))))),
    Found   = List.Select(List.Transform(Map, (m) => {m{0}, Logical(m{1})}), (p) => p{1} <> null),
    Picked  = Table.SelectColumns(Tbl, List.Transform(Found, (p) => p{1})),
    Named   = Table.RenameColumns(Picked, List.Transform(Found, (p) => {p{1}, p{0}})),
    Missing = List.Difference(List.Transform(Map, (m) => m{0}), Table.ColumnNames(Named)),
    Filled  = List.Accumulate(Missing, Named, (t, c) => Table.AddColumn(t, c, each null)),
    Typed   = Table.TransformColumnTypes(Filled, {
        {"EmployeeID", type text}, {"AssignedRoleKey", type text},
        {"AssignedRoleName", type text}, {"AssignedReason", type text},
        {"Decision", type text}, {"RejectReasons", type text},
        {"RejectComments", type text}, {"Status", type text},
        {"DecisionOn", type datetime}, {"DecisionBy", type text},
        {"LineManagerEmail", type text}
    }),
    // The app saves the line manager's address as the person typed it.
    // Lower-case it so one manager does not show up twice in a slicer.
    Lower   = Table.TransformColumns(Typed, {
        {"LineManagerEmail", each if _ = null then null else Text.Lower(Text.Trim(_)), type text}
    })
in
    Lower
