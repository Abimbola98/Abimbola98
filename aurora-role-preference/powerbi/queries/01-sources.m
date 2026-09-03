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
// the display name the app uses. 'RolePreference People' appears as something
// like cr123_rolepreferencepeople. Open the navigator once, note the real
// prefix, and substitute it throughout.
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
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferenceroles"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr123_rolekey","cr123_rolename","cr123_shortdescription","cr123_active"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr123_rolekey","RoleKey"}, {"cr123_rolename","AppRoleName"},
        {"cr123_shortdescription","ShortDescription"}, {"cr123_active","Active"}
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
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferencepeople"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr123_employeeid","cr123_name","cr123_email",
        "cr123_grade","cr123_area","cr123_team","cr123_isadmin"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr123_employeeid","EmployeeID"}, {"cr123_name","Name"},
        {"cr123_email","Email"}, {"cr123_grade","Grade"},
        {"cr123_area","Area"}, {"cr123_team","Team"}, {"cr123_isadmin","IsAdmin"}
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
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferencepreferences"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr123_employeeid","cr123_rolekey","cr123_rank",
        "cr123_submittedon","cr123_stage1status"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr123_employeeid","EmployeeID"}, {"cr123_rolekey","RoleKey"},
        {"cr123_rank","Rank"}, {"cr123_submittedon","SubmittedOn"},
        {"cr123_stage1status","Stage1Status"}
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
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferenceresponses"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr123_employeeid","cr123_rolekey","cr123_qindex",
        "cr123_responsetext","cr123_stage2status","cr123_submittedon"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr123_employeeid","EmployeeID"}, {"cr123_rolekey","RoleKey"},
        {"cr123_qindex","QIndex"}, {"cr123_responsetext","ResponseText"},
        {"cr123_stage2status","Stage2Status"}, {"cr123_submittedon","SubmittedOn"}
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
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferencealignments"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr123_employeeid","cr123_assignedrolekey","cr123_reasoning",
        "cr123_decision","cr123_rejectreasons","cr123_rejecttext",
        "cr123_status","cr123_decidedon"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr123_employeeid","EmployeeID"}, {"cr123_assignedrolekey","AssignedRoleKey"},
        {"cr123_reasoning","Reasoning"}, {"cr123_decision","Decision"},
        {"cr123_rejectreasons","RejectReasons"}, {"cr123_rejecttext","RejectText"},
        {"cr123_status","Status"}, {"cr123_decidedon","DecidedOn"}
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
             })
in
    Grp


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
