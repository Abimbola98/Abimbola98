// =============================================================================
// Aurora Preference — Power BI sources  (Power Query / M)
// =============================================================================
// TWO SOURCES, joined on RoleKey:
//
//   Dataverse  — the live app data. People, Roles, Preferences, Responses,
//                Alignments. Refreshes without a gateway.
//   CSV        — powerbi/data/roles_capacity.csv, from
//                Preference_Process_roles_available.xlsx. Post counts only.
//                Nothing else supplies these, and the app has never held them.
//
// The role dimension (DimRole) is a FULL OUTER merge of the two, so a key that
// exists on one side and not the other stays visible instead of silently
// vanishing from a chart. That join is the fragile part of this model and §4 of
// the README says what to watch.
//
// Paste each block into Home > Transform data > New Source > Blank Query >
// Advanced Editor, naming the query as its header says. Order matters where a
// query reads another.
//
// TABLE NAMES: the Dataverse connector lists tables by their LOGICAL name, not
// the display name the app uses. 'RolePreference People' appears as
// cr174_rolepreferencepeople in THIS environment. The prefix below is that
// environment's; in another one it will differ, and two of the table names are
// not just the prefix — see the note on Responses and Alignments below.
// =============================================================================


// ---- Query: EnvUrl  (parameter) --------------------------------------------
// Manage Parameters > New > Text. Example: https://org12345.crm11.dynamics.com
"https://YOUR-ORG.crm11.dynamics.com"


// ---- Query: CapacityPath  (parameter) --------------------------------------
// Manage Parameters > New > Text.
//
// A LOCAL PATH WILL NOT REFRESH IN THE SERVICE without an on-premises data
// gateway, and it only ever works from the one machine. Put the CSV in the same
// SharePoint site the team already uses and point at that instead — SharePoint
// needs no gateway, and it is also the only way anyone but you can update the
// post counts. Swap Csv.Document's File.Contents for Web.Contents(CapacityPath)
// if you use a SharePoint URL.
"C:\Aurora\roles_capacity.csv"


// ---- Query: CapacityCsv  (staging — right-click > Disable Load) ------------
let
    Source = Csv.Document(
                 File.Contents(CapacityPath),
                 [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Head   = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed  = Table.TransformColumnTypes(Head, {
        {"RoleKey", type text}, {"RoleName", type text}, {"Posts", Int64.Type},
        {"RoleFamily", type text}, {"SourceNote", type text}, {"DataIssue", type text}
    }),
    // Three source rows carry "?" instead of a key. Left as-is they would be
    // three rows sharing one key, which breaks the 1-to-many relationship
    // DimRole needs. Give each a distinct synthetic key so the posts still
    // count and the rows stay visible and findable.
    Idx    = Table.AddIndexColumn(Typed, "Idx", 1, 1, Int64.Type),
    Keyed  = Table.AddColumn(Idx, "JoinKey",
                 each if [RoleKey] = null or [RoleKey] = "" or [RoleKey] = "?"
                      then "NOKEY-" & Text.PadStart(Text.From([Idx]), 2, "0")
                      else Text.Trim([RoleKey]), type text),
    HasKey = Table.AddColumn(Keyed, "HasRealKey",
                 each not Text.StartsWith([JoinKey], "NOKEY-"), type logical),
    Out    = Table.SelectColumns(HasKey,
                 {"JoinKey","RoleName","Posts","RoleFamily","SourceNote","DataIssue","HasRealKey"})
in
    Out


// ---- Query: AppRoles  (staging — right-click > Disable Load) ---------------
// The app's own role list, straight from Dataverse.
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferenceroles"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_rolekey","cr174_rolename","cr174_shortdescription","cr174_active"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_rolekey","RoleKey"}, {"cr174_rolename","AppRoleName"},
        {"cr174_shortdescription","ShortDescription"}, {"cr174_active","Active"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"RoleKey", type text}, {"AppRoleName", type text},
        {"ShortDescription", type text}, {"Active", type logical}
    }),
    Trim   = Table.TransformColumns(Typed, {{"RoleKey", each Text.Trim(_ ?? ""), type text}})
in
    Trim


// ---- Query: DimRole  (THE role dimension — merge of both sources) ----------
// Full outer, so nothing is lost from either side. Every downstream visual and
// relationship uses this table, never CapacityCsv or AppRoles directly.
let
    Merged = Table.NestedJoin(AppRoles, {"RoleKey"}, CapacityCsv, {"JoinKey"}, "C", JoinKind.FullOuter),
    Exp    = Table.ExpandTableColumn(Merged, "C",
                 {"JoinKey","RoleName","Posts","RoleFamily","DataIssue"},
                 {"CapKey","CapRoleName","Posts","RoleFamily","CapDataIssue"}),

    // Coalesce: a row present on only one side still gets a key and a name.
    Key    = Table.AddColumn(Exp, "RoleKeyFinal", each [RoleKey] ?? [CapKey], type text),
    // The app's name wins where both exist — it is what the person actually saw
    // on screen when they ranked it.
    Name   = Table.AddColumn(Key, "RoleNameFinal",
                 each [AppRoleName] ?? [CapRoleName] ?? "(unnamed)", type text),

    Flags  = Table.AddColumn(Name, "InApp", each [RoleKey] <> null, type logical),
    Flags2 = Table.AddColumn(Flags, "InCapacitySheet", each [CapKey] <> null, type logical),
    Posts0 = Table.TransformColumns(Flags2, {{"Posts", each _ ?? 0, Int64.Type}}),

    // One column that says exactly what is wrong with a role, if anything. Put
    // it on the reconciliation page — a dashboard that hides a broken join is
    // worse than no dashboard.
    Status = Table.AddColumn(Posts0, "JoinStatus", each
                 if not [InApp] and [InCapacitySheet] and [CapDataIssue] <> null and Text.StartsWith([CapDataIssue] ?? "", "NO ROLE KEY")
                     then "Capacity sheet only - no role key"
                 else if not [InApp] and [InCapacitySheet]
                     then "Capacity sheet only - missing from the app"
                 else if [InApp] and not [InCapacitySheet]
                     then "App only - no post count"
                 else if [Posts] = 0
                     then "Matched - but zero posts"
                 else "Matched", type text),

    Out    = Table.SelectColumns(Status, {
                 "RoleKeyFinal","RoleNameFinal","Posts","RoleFamily",
                 "Active","InApp","InCapacitySheet","JoinStatus"
             }),
    Ren    = Table.RenameColumns(Out, {{"RoleKeyFinal","RoleKey"},{"RoleNameFinal","RoleName"}}),
    Fam    = Table.TransformColumns(Ren, {{"RoleFamily", each _ ?? "(unknown)", type text}}),
    // RoleKey must be unique for the 1-to-many relationships. NOKEY-nn keeps the
    // three unkeyed capacity rows distinct; this guards against anything else.
    Dedup  = Table.Distinct(Fam, {"RoleKey"})
in
    Dedup


// ---- Query: People ---------------------------------------------------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepeople"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeid","cr174_name","cr174_email",
        "cr174_grade","cr174_area","cr174_team","cr174_isadmin"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeid","EmployeeID"}, {"cr174_name","Name"},
        {"cr174_email","Email"}, {"cr174_grade","Grade"},
        {"cr174_area","Area"}, {"cr174_team","Team"}, {"cr174_isadmin","IsAdmin"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"Name", type text}, {"Email", type text},
        {"Grade", type text}, {"Area", type text}, {"Team", type text},
        {"IsAdmin", type logical}
    }),
    // Trim and upper-case so "g6 " and "G6" do not become two grades.
    Clean  = Table.TransformColumns(Typed, {
        {"Grade", each Text.Upper(Text.Trim(_ ?? "")), type text},
        {"Area",  each Text.Trim(_ ?? ""), type text},
        {"Team",  each Text.Trim(_ ?? ""), type text}
    }),
    IsMgr  = Table.AddColumn(Clean, "IsLineManager",
                 each List.Contains({"G6","G7"}, [Grade]), type logical)
in
    IsMgr


// ---- Query: Preferences  (one row per person per ranked role) --------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepreferences"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeid","cr174_rolekey","cr174_rank",
        "cr174_submittedon","cr174_stage1status"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeid","EmployeeID"}, {"cr174_rolekey","RoleKey"},
        {"cr174_rank","Rank"}, {"cr174_submittedon","SubmittedOn"},
        {"cr174_stage1status","Stage1Status"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"RoleKey", type text}, {"Rank", Int64.Type},
        {"SubmittedOn", type datetime}, {"Stage1Status", type text}
    }),
    Trim   = Table.TransformColumns(Typed, {{"RoleKey", each Text.Trim(_ ?? ""), type text}}),
    // Withdrawn is a dead status in the app but legacy rows may survive.
    Live   = Table.SelectRows(Trim, each [Stage1Status] <> "Withdrawn"),
    Ranked = Table.SelectRows(Live, each [Rank] <> null and [Rank] > 0)
in
    Ranked


// ---- Query: Responses  (the Stage-2 free text) -----------------------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepreferenceresponses"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeid","cr174_rolekey","cr174_qindex",
        "cr174_responsetext","cr174_stage2status","cr174_submittedon"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeid","EmployeeID"}, {"cr174_rolekey","RoleKey"},
        {"cr174_qindex","QIndex"}, {"cr174_responsetext","ResponseText"},
        {"cr174_stage2status","Stage2Status"}, {"cr174_submittedon","SubmittedOn"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"RoleKey", type text}, {"QIndex", Int64.Type},
        {"ResponseText", type text}, {"Stage2Status", type text},
        {"SubmittedOn", type datetime}
    }),
    QLabel = Table.AddColumn(Typed, "Question",
                 each if [QIndex] = 0 then "Q1 Why this preference"
                      else "Q2 Skills and experience", type text),
    Words  = Table.AddColumn(QLabel, "WordCount",
                 each List.Count(List.Select(
                     Text.Split(
                         Text.Replace(Text.Replace([ResponseText] ?? "", "#(lf)", " "), "#(cr)", " "),
                         " "),
                     each Text.Trim(_) <> "")), Int64.Type)
in
    Words


// ---- Query: Alignments  (Phase 2 — accept / challenge) ---------------------
// Only exists once the Alignments table has been created in Dataverse. If it
// has not, right-click this query and Disable Load rather than deleting it —
// the pages that use it show blank instead of erroring.
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencealignment"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeid","cr174_assignedrolekey","cr174_reasoning",
        "cr174_decision","cr174_rejectreasons","cr174_rejecttext",
        "cr174_status","cr174_decidedon"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeid","EmployeeID"}, {"cr174_assignedrolekey","AssignedRoleKey"},
        {"cr174_reasoning","Reasoning"}, {"cr174_decision","Decision"},
        {"cr174_rejectreasons","RejectReasons"}, {"cr174_rejecttext","RejectText"},
        {"cr174_status","Status"}, {"cr174_decidedon","DecidedOn"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"AssignedRoleKey", type text},
        {"Reasoning", type text}, {"Decision", type text},
        {"RejectReasons", type text}, {"RejectText", type text},
        {"Status", type text}, {"DecidedOn", type datetime}
    })
in
    Typed


// ---- Query: RejectReasonsUnpivoted  (tick-box analysis) --------------------
// The app stores ticked reasons as ONE ";"-separated string. Split to rows so a
// reason can be counted and cross-filtered like a proper dimension.
let
    Source  = Alignments,
    Rejects = Table.SelectRows(Source, each [Decision] = "Reject"
                                        and [RejectReasons] <> null
                                        and [RejectReasons] <> ""),
    Split   = Table.AddColumn(Rejects, "Reason",
                  each List.Select(
                      List.Transform(Text.Split([RejectReasons], ";"), Text.Trim),
                      each _ <> ""), type list),
    Expand  = Table.ExpandListColumn(Split, "Reason"),
    Keep    = Table.SelectColumns(Expand, {"EmployeeID","AssignedRoleKey","Reason","DecidedOn"}),
    Typed   = Table.TransformColumnTypes(Keep, {{"Reason", type text}})
in
    Typed


// ---- Query: PreferenceWide  (one row per respondent, 3 preference columns) --
// Feeds the what-if page and the respondent table.
let
    Source = Preferences,
    Top3   = Table.SelectRows(Source, each [Rank] <= 3),
    Piv    = Table.Pivot(
                 Table.AddColumn(Top3, "PrefCol", each "Pref" & Text.From([Rank]), type text),
                 {"Pref1","Pref2","Pref3"}, "PrefCol", "RoleKey"),
    Grp    = Table.Group(Piv, {"EmployeeID"}, {
                 {"Pref1", each List.Max([Pref1]), type text},
                 {"Pref2", each List.Max([Pref2]), type text},
                 {"Pref3", each List.Max([Pref3]), type text},
                 {"SubmittedOn", each List.Max([SubmittedOn]), type datetime}
             }),

    // Resolve the keys to names. The respondent table and the what-if table both
    // show role NAMES, and a model cannot do this with relationships: only one
    // active path is allowed between two tables, so three key columns pointing at
    // DimRole would need three inactive relationships and a USERELATIONSHIP
    // measure each, returning text into a table visual. Three merges here instead.
    // DimRole is the single role dimension, so this picks up the app's name where
    // there is one and the capacity sheet's where the role is sheet-only.
    J1   = Table.NestedJoin(Grp, {"Pref1"}, DimRole, {"RoleKey"}, "D1", JoinKind.LeftOuter),
    E1   = Table.ExpandTableColumn(J1, "D1", {"RoleName"}, {"Pref1Name"}),
    J2   = Table.NestedJoin(E1,  {"Pref2"}, DimRole, {"RoleKey"}, "D2", JoinKind.LeftOuter),
    E2   = Table.ExpandTableColumn(J2, "D2", {"RoleName"}, {"Pref2Name"}),
    J3   = Table.NestedJoin(E2,  {"Pref3"}, DimRole, {"RoleKey"}, "D3", JoinKind.LeftOuter),
    E3   = Table.ExpandTableColumn(J3, "D3", {"RoleName"}, {"Pref3Name"}),

    // Two different nulls, and they must not read the same on the page:
    //   key null      -> the person has fewer than three eligible roles. Blank is
    //                    the honest cell; there is no third preference to show.
    //   key unmatched -> a BROKEN JOIN. Somebody ranked a key DimRole does not
    //                    have. Blank would read as "no answer" and hide it, so
    //                    say so in the cell and go and look at page 6.
    // The app makes people rank every role they are eligible for (scrForm blocks
    // submit unless all of colRanks carries a distinct rank), so someone eligible
    // for one or two roles genuinely has no Pref3 — this is not an edge case.
    // Built as new columns and swapped in, rather than transformed in place: a
    // transform cannot see a sibling column, and the rule here depends on one.
    L1    = Table.AddColumn(E3, "P1", each
                if [Pref1] = null then null else ([Pref1Name] ?? "(unknown role)"), type text),
    L2    = Table.AddColumn(L1, "P2", each
                if [Pref2] = null then null else ([Pref2Name] ?? "(unknown role)"), type text),
    L3    = Table.AddColumn(L2, "P3", each
                if [Pref3] = null then null else ([Pref3Name] ?? "(unknown role)"), type text),
    Drop  = Table.RemoveColumns(L3, {"Pref1Name","Pref2Name","Pref3Name"}),
    Final = Table.RenameColumns(Drop, {
                {"P1","Pref1Name"}, {"P2","Pref2Name"}, {"P3","Pref3Name"}
            })
in
    Final


// ---- Query: RoleReconciliation  (put this on its own page) -----------------
// Everything the two sources disagree about, in one table. Check it after every
// refresh: a role that drops out of the join disappears from the heatmap
// without any error, and the totals quietly stop adding up.
let
    Source = DimRole,
    Bad    = Table.SelectRows(Source, each [JoinStatus] <> "Matched"),
    Sorted = Table.Sort(Bad, {{"JoinStatus", Order.Ascending}, {"RoleKey", Order.Ascending}})
in
    Sorted
