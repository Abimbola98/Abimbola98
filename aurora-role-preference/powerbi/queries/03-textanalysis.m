// =============================================================================
// Word frequency and theme tagging for the free text  (Power Query / M)
// =============================================================================
// Feeds the word cloud and the theme bar chart on the trends page. Runs
// entirely inside Power BI Desktop — NO Premium capacity, NO Azure key, no data
// leaving the tenant. Read the note on real sentiment at the bottom before
// promising anyone machine learning.
// =============================================================================


// ---- Query: StopWords ------------------------------------------------------
// Without this the cloud is just "the", "and", "to". The second list is the
// domain-specific part: words that are true of every answer in this process and
// therefore say nothing about any of them.
let
    Common = {
        "the","and","to","of","a","in","is","it","for","that","this","with","as",
        "my","i","be","have","has","had","would","will","was","were","are","am",
        "on","at","by","or","an","if","from","but","not","no","so","do","does",
        "did","can","could","should","been","being","which","what","when","where",
        "who","how","there","their","they","them","we","us","our","you","your",
        "me","he","she","his","her","also","very","more","most","much","many",
        "some","any","all","both","each","other","than","then","because","about",
        "into","over","under","between","within","across","during","before","after"
    },
    Domain = {
        "role","roles","team","teams","work","working","job","post","posts",
        "would","like","think","feel","want","area","areas","new","also",
        "preference","preferences","aurora","ea","agency","environment"
    },
    All = List.Distinct(Common & Domain),
    Tbl = Table.FromList(All, Splitter.SplitByNothing(), {"Word"}, null, ExtraValues.Error)
in
    Tbl


// ---- Query: WordFrequency --------------------------------------------------
// Source can be swapped between Responses (Stage-2 answers) and the rejection
// free text — or unioned. Keep them separate: what people say about wanting a
// role and what they say about turning one down are different questions.
let
    Source   = Responses,
    Text0    = Table.SelectColumns(
                   Table.SelectRows(Source, each [ResponseText] <> null and Text.Trim([ResponseText]) <> ""),
                   {"EmployeeID","RoleKey","ResponseText"}),

    // lower-case, strip punctuation to spaces, split, drop short words + stopwords
    Lower    = Table.TransformColumns(Text0, {{"ResponseText", Text.Lower, type text}}),
    Clean    = Table.TransformColumns(Lower, {{"ResponseText",
                   each Text.Combine(List.Transform(Text.ToList(_),
                       each if List.Contains({"a".."z"}, _) or _ = " " then _ else " ")), type text}}),
    Split    = Table.AddColumn(Clean, "Word",
                   each List.Select(Text.Split([ResponseText], " "), each Text.Length(_) > 3), type list),
    Expand   = Table.ExpandListColumn(Split, "Word"),
    NoStop   = Table.NestedJoin(Expand, {"Word"}, StopWords, {"Word"}, "S", JoinKind.LeftAnti),
    Grouped  = Table.Group(NoStop, {"Word"}, {
                   {"Frequency", each Table.RowCount(_), Int64.Type},
                   {"People", each List.Count(List.Distinct(_[EmployeeID])), Int64.Type}
               }),
    // "People" is the honest measure for a cloud: one person writing "flood"
    // eleven times should not outrank eleven people writing it once.
    Sorted   = Table.Sort(Grouped, {{"People", Order.Descending}, {"Frequency", Order.Descending}}),
    TopN     = Table.SelectRows(Sorted, each [People] >= 2)
in
    TopN


// ---- Query: ThemeKeywords --------------------------------------------------
// Deterministic theme tagging: a keyword list per theme, editable by the people
// who actually read the answers. Cruder than a model, but it is auditable and
// arguable — you can point at exactly why an answer was tagged, which matters
// for a process that affects someone's job.
let
    Rows = {
        {"Location / travel",      "location,travel,commute,distance,office,base,home,relocate,miles,patch"},
        {"Existing relationships", "relationship,network,stakeholder,partner,rma,contacts,known,established"},
        {"Current activity",       "currently,already,doing,undertake,existing,continue,same,familiar"},
        {"Skills and experience",  "experience,skill,qualification,expertise,background,trained,knowledge"},
        {"Development / career",   "develop,career,progress,grow,stretch,opportunity,learn,promotion"},
        {"Specific interest",      "interest,carbon,flood,coastal,asset,nature,climate,passion,specialism"},
        {"Workload / capacity",    "workload,capacity,pressure,busy,resource,bandwidth,stress"},
        {"Grade / pay",            "grade,pay,salary,band,downgrade,demotion,regrade"}
    },
    Tbl   = Table.FromRows(Rows, {"Theme","Keywords"}),
    Split = Table.AddColumn(Tbl, "Keyword",
                each List.Transform(Text.Split([Keywords], ","), Text.Trim), type list),
    Exp   = Table.ExpandListColumn(Split, "Keyword"),
    Out   = Table.SelectColumns(Exp, {"Theme","Keyword"})
in
    Out


// ---- Query: ResponseThemes -------------------------------------------------
// One row per response per theme matched. A response can carry several themes;
// that is deliberate — people give more than one reason.
let
    Source  = Table.SelectRows(Responses, each [ResponseText] <> null and Text.Trim([ResponseText]) <> ""),
    Lower   = Table.AddColumn(Source, "Lower", each Text.Lower([ResponseText]), type text),
    Matched = Table.AddColumn(Lower, "Themes",
                  each let t = [Lower] in
                      List.Distinct(
                          List.Select(
                              List.Transform(Table.ToRecords(ThemeKeywords),
                                  each if Text.Contains(t, _[Keyword]) then _[Theme] else null),
                              each _ <> null)), type list),
    Exp     = Table.ExpandListColumn(Matched, "Themes"),
    Named   = Table.RenameColumns(Exp, {{"Themes","Theme"}}),
    Keep    = Table.SelectColumns(Named, {"EmployeeID","RoleKey","QIndex","Theme"}),
    Typed   = Table.TransformColumnTypes(Keep, {{"Theme", type text}})
in
    Typed


// =============================================================================
// ON SENTIMENT ANALYSIS — read before promising it
// =============================================================================
// The brief asks for "sentiment analysis (machine learning)". Three options,
// and the differences matter:
//
// 1. Power BI AI Insights > Text Analytics > Score sentiment.
//    Two clicks in Power Query. REQUIRES a Premium capacity or Premium Per User
//    licence — it is greyed out on Pro. Text is sent to Azure Cognitive Services
//    for scoring, which is a data-protection question for OFFICIAL SENSITIVE
//    free text about people's jobs: it needs checking against the privacy notice
//    the app already shows, which says data is held in a virtual database and
//    destroyed after two years. Do not switch it on without that check.
//
// 2. Azure Cognitive Services / AI Language via a custom connector or Azure
//    Function. Same data-protection question, more setup, works on Pro.
//
// 3. The theme tagging above. No licence, no data leaving the tenant, fully
//    auditable. It gives you WHAT people are talking about, not how they feel
//    about it.
//
// My recommendation is to ship 3 now and treat 1 as a later decision with the
// information-governance answer attached. A sentiment score on ~100 answers is
// also thin evidence: with this volume, reading them is both feasible and
// better, and the brief already says decisions will be made by reading the
// comments. The dashboard's job is to point at which ones to read first, and
// theme tags plus word frequency do that.
//
// If you do enable option 1, the sentiment score arrives as a 0..1 column; add
// it to Responses and the measures file has a commented-out block ready for it.
// =============================================================================
