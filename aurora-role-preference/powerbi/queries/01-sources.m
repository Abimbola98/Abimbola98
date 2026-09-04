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
// Manage Parameters > New > Text.
// The BARE HOST, no scheme: orgb83df62a.crm11.dynamics.com
// CommonDataService.Database takes the host, not a URL. Passing
// https://... in front of it is the first thing to check if the source step
// errors.
"https://YOUR-ORG.crm11.dynamics.com"


// ---- Query: CapacityPath  (parameter — NOT NEEDED as things stand) ---------
// The post counts are embedded in queries/00-capacity-data.m, so there is no
// file to point at and this parameter is unused. Do not create it.
//
// It stays documented because it is the way back: if the numbers ever need to
// be maintained by someone without Power BI Desktop, put the CSV on SharePoint,
// create CapacityPath as Text, and change CapacityCsv's Source line from
// Csv.Document(CapacityText, …) to
// Csv.Document(Web.Contents(CapacityPath), …). Nothing else changes — the
// parsing, typing and NOKEY handling below are identical either way.
// A LOCAL path is the one option to avoid: it needs an on-premises gateway to
// refresh in the Service and only ever works from the machine holding it.
"C:\Aurora\roles_capacity.csv"


// ---- Query: CapacityCsv  (staging — right-click > Disable Load) ------------
let
    // CapacityText is the embedded CSV — see queries/00-capacity-data.m for why
    // the numbers are in M rather than in a file, and how to go back to a file.
    Source = Csv.Document(
                 CapacityText,
                 [Delimiter=",", Encoding=65001, QuoteStyle=QuoteStyle.Csv]),
    Head   = Table.PromoteHeaders(Source, [PromoteAllScalars=true]),
    Typed  = Table.TransformColumnTypes(Head, {
        {"RoleKey", type text}, {"RoleName", type text}, {"Posts", Int64.Type},
        {"RoleFamily", type text}, {"RoleDirectorate", type text},
        {"SourceNote", type text}, {"DataIssue", type text}
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
                 {"JoinKey","RoleName","Posts","RoleFamily","RoleDirectorate",
                  "SourceNote","DataIssue","HasRealKey"})
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
        // RoleName -> AppRoleName is the ONE deliberate divergence from the
        // Dataverse name: the capacity CSV also has a RoleName, and DimRole
        // merges the two. Distinct names keep that merge readable.
        {"cr174_rolekey","RoleKey"}, {"cr174_rolename","AppRoleName"},
        {"cr174_shortdescription","ShortDescription"}, {"cr174_active","Active"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"RoleKey", type text}, {"AppRoleName", type text},
        {"ShortDescription", type text}
    }),
    // Active is a Dataverse Yes/No. Over the TDS endpoint that arrives as a
    // logical or as 0/1 depending on how the column was defined, so coerce it
    // rather than declaring a type that may not fit and failing the refresh.
    Act    = Table.AddColumn(Typed, "ActiveFlag",
                 each [Active] = true or [Active] = 1, type logical),
    Flag   = Table.RenameColumns(Table.RemoveColumns(Act, {"Active"}), {{"ActiveFlag","Active"}}),
    Trim   = Table.TransformColumns(Flag, {{"RoleKey", each Text.Trim(_ ?? ""), type text}})
in
    Trim


// ---- Query: DimRole  (THE role dimension — merge of both sources) ----------
// Full outer, so nothing is lost from either side. Every downstream visual and
// relationship uses this table, never CapacityCsv or AppRoles directly.
let
    Merged = Table.NestedJoin(AppRoles, {"RoleKey"}, CapacityCsv, {"JoinKey"}, "C", JoinKind.FullOuter),
    Exp    = Table.ExpandTableColumn(Merged, "C",
                 {"JoinKey","RoleName","Posts","RoleFamily","RoleDirectorate","DataIssue"},
                 {"CapKey","CapRoleName","Posts","RoleFamily","RoleDirectorate","CapDataIssue"}),

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
                 "RoleKeyFinal","RoleNameFinal","Posts","RoleFamily","RoleDirectorate",
                 "Active","InApp","InCapacitySheet","JoinStatus"
             }),
    Ren    = Table.RenameColumns(Out, {{"RoleKeyFinal","RoleKey"},{"RoleNameFinal","RoleName"}}),
    // Both groupings come only from the capacity sheet, so an app-only role has
    // neither. "(unknown)" keeps it visible in a legend instead of dropping it.
    Fam    = Table.TransformColumns(Ren, {
                 {"RoleFamily",      each _ ?? "(unknown)", type text},
                 {"RoleDirectorate", each _ ?? "(unknown)", type text}
             }),
    // RoleKey must be unique for the 1-to-many relationships. NOKEY-nn keeps the
    // three unkeyed capacity rows distinct; this guards against anything else.
    Dedup  = Table.Distinct(Fam, {"RoleKey"})
in
    Dedup


// ---- Query: People ---------------------------------------------------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepeople"]}[Data],
    // NOTE THE GRADE COLUMN. There is no cr174_grade on this table. Grade lives
    // in cr174_gradeareateam — docs/dataverse-setup.md lists Grade, Area and Team
    // as three rows of one schema table, and whoever built it created a single
    // column from that heading. Dataverse freezes a logical name at creation, so
    // renaming the display name to "Grade" afterwards left the logical name as
    // it is. Area and Team were then added properly. CONFIRMED against the data:
    // it holds the grade alone ("SG6"), not a composite. Renamed to Grade here so
    // nothing downstream inherits the misnomer.
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeid","cr174_name","cr174_email",
        "cr174_gradeareateam","cr174_area","cr174_team","cr174_isadmin"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeid","EmployeeID"}, {"cr174_name","Name"},
        {"cr174_email","Email"}, {"cr174_gradeareateam","Grade"},
        {"cr174_area","Area"}, {"cr174_team","Team"}, {"cr174_isadmin","IsAdmin"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"Name", type text}, {"Email", type text},
        {"Grade", type text}, {"Area", type text}, {"Team", type text}
    }),
    // Trim and upper-case so "g6 " and "G6" do not become two grades.
    Clean  = Table.TransformColumns(Typed, {
        {"Grade", each Text.Upper(Text.Trim(_ ?? "")), type text},
        {"Area",  each Text.Trim(_ ?? ""), type text},
        {"Team",  each Text.Trim(_ ?? ""), type text}
    }),
    // IsAdmin is Yes/No — same coercion as Active on AppRoles.
    Adm    = Table.AddColumn(Clean, "IsAdminFlag",
                 each [IsAdmin] = true or [IsAdmin] = 1, type logical),
    Adm2   = Table.RenameColumns(Table.RemoveColumns(Adm, {"IsAdmin"}), {{"IsAdminFlag","IsAdmin"}}),

    // *** CONFIRM THIS LIST WITH THE BUSINESS BEFORE TRUSTING Total Line Managers. ***
    // The brief says "line managers G6/G7". The grades actually in the app are
    // SG5, SG6 and G7 — Environment Agency staff grades, where SG6 is not
    // obviously the same thing as G6. A wrong list here does not error; it just
    // returns a confidently wrong headline card.
    MgrGrades = {"G6","G7"},
    IsMgr  = Table.AddColumn(Adm2, "IsLineManager",
                 each List.Contains(MgrGrades, [Grade]), type logical)
in
    IsMgr


// ---- Query: Preferences  (one row per person per ranked role) --------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepreferences"]}[Data],
    // NOTE THE EMPLOYEE ID COLUMN. There is no cr174_employeeid on this table.
    // docs/dataverse-setup.md compresses two columns into the single schema row
    // "EmployeeID / RoleKey", and whoever built the table created one column from
    // that heading before adding RoleKey separately. The logical name froze as
    // cr174_employeeidrolekey; the display name the app patches is EmployeeID.
    // CONFIRMED against the data: it holds the plain id ("60412"), not a
    // composite. Renamed to EmployeeID here so nothing downstream inherits the
    // misnomer.
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
    // Withdrawn is a dead status in the app but legacy rows may survive.
    Live   = Table.SelectRows(Trim, each [Stage1Status] <> "Withdrawn"),
    Ranked = Table.SelectRows(Live, each [Rank] <> null and [Rank] > 0)
in
    Ranked


// ---- Query: Responses  (the Stage-2 free text) -----------------------------
let
    Source = CommonDataService.Database(EnvUrl),
    Tbl    = Source{[Schema="dbo", Item="cr174_rolepreferencepreferenceresponses"]}[Data],
    // NOTE THE EMPLOYEE ID COLUMN. There is no cr174_employeeid on this table.
    // docs/dataverse-setup.md compresses two columns into the single schema row
    // "EmployeeID / RoleKey", and whoever built the table created one column from
    // that heading before adding RoleKey separately. The logical name froze as
    // cr174_employeeidrolekey; the display name the app patches is EmployeeID.
    // CONFIRMED against the data: it holds the plain id ("60412"), not a
    // composite. Renamed to EmployeeID here so nothing downstream inherits the
    // misnomer.
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeidrolekey","cr174_rolekey","cr174_qindex",
        "cr174_responsetext","cr174_stage2status","cr174_submittedon",
        "cr174_questiontext"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeidrolekey","EmployeeID"}, {"cr174_rolekey","RoleKey"},
        {"cr174_qindex","QIndex"}, {"cr174_responsetext","ResponseText"},
        {"cr174_stage2status","Stage2Status"}, {"cr174_submittedon","SubmittedOn"},
        {"cr174_questiontext","QuestionText"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"RoleKey", type text}, {"QIndex", Int64.Type},
        {"ResponseText", type text}, {"Stage2Status", type text},
        {"SubmittedOn", type datetime}, {"QuestionText", type text}
    }),
    // The app stores the question it actually asked, so use that and keep the
    // derived label only as a fallback for rows written before it did.
    QLabel = Table.AddColumn(Typed, "Question",
                 each if [QuestionText] <> null and Text.Trim([QuestionText]) <> ""
                      then [QuestionText]
                      else if [QIndex] = 0 then "Q1 Why this preference"
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
    // Model names deliberately match the Dataverse display names one-for-one, so
    // a reader who sees AssignedReason on a visual can go and find AssignedReason
    // in the table. AssignedRoleName is a bonus — Kate/Claire type the role name
    // straight into it, so page 5 needs no lookup to DimRole.
    Cols   = Table.SelectColumns(Tbl, {
        "cr174_employeeid","cr174_assignedrolekey","cr174_assignedrolename",
        "cr174_assignedreason","cr174_decision","cr174_rejectreasons",
        "cr174_rejectcomments","cr174_status","cr174_decisionon"
    }),
    Named  = Table.RenameColumns(Cols, {
        {"cr174_employeeid","EmployeeID"}, {"cr174_assignedrolekey","AssignedRoleKey"},
        {"cr174_assignedrolename","AssignedRoleName"},
        {"cr174_assignedreason","AssignedReason"}, {"cr174_decision","Decision"},
        {"cr174_rejectreasons","RejectReasons"}, {"cr174_rejectcomments","RejectComments"},
        {"cr174_status","Status"}, {"cr174_decisionon","DecisionOn"}
    }),
    Typed  = Table.TransformColumnTypes(Named, {
        {"EmployeeID", type text}, {"AssignedRoleKey", type text},
        {"AssignedRoleName", type text},
        {"AssignedReason", type text}, {"Decision", type text},
        {"RejectReasons", type text}, {"RejectComments", type text},
        {"Status", type text}, {"DecisionOn", type datetime}
    })
in
    Typed


// ---- Query: RejectReasonsUnpivoted  (tick-box analysis) --------------------
// The app stores ticked reasons as ONE ";"-separated string. Split to rows so a
// reason can be counted and cross-filtered like a proper dimension.
let
    Source  = Alignments,
    // The app writes "Accepted" / "Rejected", not "Accept" / "Reject" — see
    // Phase2-alignment-formulas.powerfx. Getting this wrong returns zero rows
    // with no error and page 5 reads as "nobody challenged anything".
    Rejects = Table.SelectRows(Source, each [Decision] = "Rejected"
                                        and [RejectReasons] <> null
                                        and [RejectReasons] <> ""),

    // Nobody has challenged an alignment yet, and for most of this process
    // nobody will have. An empty source must therefore produce a correctly
    // TYPED empty table, not an error and not a table with no columns: the
    // relationship to People and every page-5 measure are built against these
    // column names long before the first rejection exists. Deriving the shape
    // from zero rows is what the split-and-expand path cannot do.
    Shape   = type table [EmployeeID = text, AssignedRoleKey = text,
                          Reason = text, DecisionOn = datetime],
    Out     = if Table.IsEmpty(Rejects) then #table(Shape, {}) else
                  let
                      Split  = Table.AddColumn(Rejects, "Reason",
                                   each List.Select(
                                       List.Transform(Text.Split([RejectReasons], ";"), Text.Trim),
                                       each _ <> ""), type list),
                      Expand = Table.ExpandListColumn(Split, "Reason"),
                      Keep   = Table.SelectColumns(Expand,
                                   {"EmployeeID","AssignedRoleKey","Reason","DecisionOn"}),
                      Typed  = Table.TransformColumnTypes(Keep, {{"Reason", type text}})
                  in
                      Typed
in
    Out


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
