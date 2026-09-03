// =============================================================================
// Aurora Preference — Power BI sources  (Power Query / M)
// =============================================================================
// Paste each block below into Home > Transform data > New Source > Blank Query >
// Advanced Editor, naming the query as the header says.
//
// Set EnvUrl to your Dataverse environment URL first — every table query reads
// it, so it is the only thing to change between Dev/Test/Prod.
//
// TABLE NAMES: Power BI's Dataverse connector lists tables by their LOGICAL
// name, not the display name the app uses. 'RolePreference People' will appear
// as something like cr123_rolepreferencepeople. Open the navigator once, note
// the real names, and substitute them below.
// =============================================================================


// ---- Query: EnvUrl  (parameter) --------------------------------------------
// Manage Parameters > New > Text. Example: https://org12345.crm11.dynamics.com
"https://YOUR-ORG.crm11.dynamics.com"


// ---- Query: People ---------------------------------------------------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferencepeople"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {
        "cr123_employeeid", "cr123_name", "cr123_email",
        "cr123_grade", "cr123_area", "cr123_team", "cr123_isadmin"
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
    // Grade drives the "line managers G6/G7" card. Trim and upper-case so
    // "g6 " and "G6" do not become two different grades.
    Clean  = Table.TransformColumns(Typed, {
        {"Grade", each Text.Upper(Text.Trim(_ ?? "")), type text},
        {"Area",  each Text.Trim(_ ?? ""), type text},
        {"Team",  each Text.Trim(_ ?? ""), type text}
    }),
    IsMgr  = Table.AddColumn(Clean, "IsLineManager",
                 each List.Contains({"G6","G7"}, [Grade]), type logical)
in
    IsMgr


// ---- Query: RolesCapacity --------------------------------------------------
// From powerbi/data/roles_capacity.csv (generated from
// Preference_Process_roles_available.xlsx). Point the path at wherever you put
// the file, or host it on SharePoint and use SharePoint.Files instead.
let
    Source = Csv.Document(
                 File.Contents("C:\Aurora\roles_capacity.csv"),
                 [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Head   = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed  = Table.TransformColumnTypes(Head, {
        {"RoleKey", type text}, {"RoleName", type text}, {"Posts", Int64.Type},
        {"RoleFamily", type text}, {"SourceNote", type text},
        {"DataIssue", type text}
    }),
    // Three source rows have "?" instead of a key and cannot be joined to app
    // data. They are KEPT so the post totals stay honest, but flagged.
    Keyed  = Table.AddColumn(Typed, "HasKey",
                 each [RoleKey] <> null and [RoleKey] <> "" and [RoleKey] <> "?",
                 type logical)
in
    Keyed


// ---- Query: Roles  (the app's own role list) -------------------------------
// Kept separate from RolesCapacity on purpose: comparing the two is how you
// find keys that exist in one and not the other. R08 was exactly this — present
// in the capacity sheet, absent from the app, so the option rendered blank.
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr123_rolepreferenceroles"]}[Data],
    Cols   = Table.SelectColumns(Tbl, {"cr123_rolekey","cr123_rolename","cr123_active"}),
    Named  = Table.RenameColumns(Cols, {
        {"cr123_rolekey","RoleKey"}, {"cr123_rolename","AppRoleName"},
        {"cr123_active","Active"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"RoleKey", type text}, {"AppRoleName", type text}, {"Active", type logical}
    })
in
    Typed


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
    // Withdrawn is a dead status in the app but legacy rows may survive.
    Live   = Table.SelectRows(Typed, each [Stage1Status] <> "Withdrawn"),
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
    Words  = Table.AddColumn(Typed, "WordCount",
                 each List.Count(List.Select(
                     Text.Split(Text.Replace(Text.Replace([ResponseText] ?? "", "#(lf)", " "), "#(cr)", " "), " "),
                     each Text.Trim(_) <> "")), Int64.Type)
in
    Table.Join(QLabel, "EmployeeID", Table.SelectColumns(Words, {"EmployeeID"}), "EmployeeID", JoinKind.LeftOuter)


// ---- Query: Alignments  (Phase 2 — accept / challenge) ---------------------
// Only exists once the Alignments table has been created in Dataverse. If it
// has not, right-click this query and Disable Load rather than deleting it —
// the pages that use it will show blank instead of erroring.
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
// reason can be counted, filtered and cross-filtered like a proper dimension.
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
// Feeds the what-if page and the respondent table. Built here rather than in
// DAX so the assignment query below can consume it directly.
let
    Source = Preferences,
    Top3   = Table.SelectRows(Source, each [Rank] <= 3),
    Piv    = Table.Pivot(
                 Table.TransformColumnTypes(
                     Table.AddColumn(Top3, "PrefCol", each "Pref" & Text.From([Rank]), type text),
                     {{"PrefCol", type text}}),
                 {"Pref1","Pref2","Pref3"}, "PrefCol", "RoleKey"),
    Grp    = Table.Group(Piv, {"EmployeeID"}, {
                 {"Pref1", each List.Max([Pref1]), type text},
                 {"Pref2", each List.Max([Pref2]), type text},
                 {"Pref3", each List.Max([Pref3]), type text},
                 {"SubmittedOn", each List.Max([SubmittedOn]), type datetime}
             })
in
    Grp
