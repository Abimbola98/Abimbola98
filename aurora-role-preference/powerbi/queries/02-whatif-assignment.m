// =============================================================================
// What-if: two-pass capacitated assignment  (Power Query / M)
// =============================================================================
// "If we allocated now, how many people get a role they argued for, how many
// have to be placed below that line, and how many cannot be placed at all?"
//
// THE JUSTIFICATION LINE is the idea this model is built around. People rank
// every role they are eligible for — up to 12 in the current data — but they
// only write a justification for their TOP THREE. Those three are the choices
// they made a case for; ranks 4 and below are ordering, not argument.
//
// So the allocation runs in two passes:
//
//   PASS 1  Everyone, in shuffled order, competes for their top three only.
//           Justified preferences get first claim on every post.
//   PASS 2  Anyone still unplaced walks down ranks 4, 5, 6 … against whatever
//           capacity survived pass 1.
//
// Two passes rather than one, deliberately. In a single pass someone early in
// the shuffle takes a post as their 7th choice that someone later needed as
// their 1st — which inverts the priority the justification process establishes.
// Two passes make justified preferences senior to unjustified ones by
// construction, which is what the process actually means.
//
// This produces THREE outcome bands, and the middle one is the point:
//
//   Justified choice              got 1st, 2nd or 3rd — the headline
//   Below the justification line  got a role they ranked but did not argue for
//                                 — a conversation, and this sizes how many
//   Unplaceable                   every role they ranked is full — the number
//                                 that should worry somebody
//
// A single "Unassigned" figure conflates the last two, and they need completely
// different responses. That was the reason for the rewrite.
//
// WHAT THIS STILL DOES NOT TELL YOU. The order decides who wins a contested
// role, so no individual row is a decision. Two passes make the BANDS more
// meaningful; they do not make any one person's outcome real. Run it at three
// or four seeds and report whether the band sizes move — with a real
// "unplaceable" number in play that check matters more, not less.
//
// Why Power Query and not DAX: allocation is sequential — each person changes
// the capacity the next person sees. DAX has no clean way to carry that state
// down a table. List.Accumulate does exactly this.
//
// Determinism: Number.Random() would give a different answer on every refresh
// and break any conversation about the numbers. The order comes from a hash of
// EmployeeID mixed with WhatIfSeed, so a given seed always reproduces its run
// and changing the seed gives an independent one.
// =============================================================================


// ---- Query: WhatIfSeed  (parameter) ----------------------------------------
// Manage Parameters > New. Whole Number if offered, Decimal Number otherwise —
// WhatIfSeedValue coerces it either way. Change it to re-roll.
1


// ---- Query: WhatIfSeedValue  (LOAD this one) -------------------------------
// DAX cannot read a Power Query parameter — parameters are scalars and never
// reach the model as tables, so SELECTEDVALUE(WhatIfSeed[...]) has nothing to
// bind to. This one-row table carries the seed across so the What If Caveat
// measure can name the run it is describing. No relationships: it is a caption
// lookup and nothing else.
//
// Int64.From, not a bare WhatIfSeed: the parameter may have been created as a
// Decimal Number (Desktop does not always offer Whole Number), and ascribing
// Int64.Type to a decimal makes the table claim a type it does not hold.
let
    Out = Table.FromRecords(
              {[Seed = Int64.From(WhatIfSeed)]},
              type table [Seed = Int64.Type])
in
    Out


// ---- Query: WhatIfAssignment -----------------------------------------------
let
    // ---------- capacity ----------
    // Only roles that exist on BOTH sides can be assigned: a capacity row with
    // no key matches nobody's preference, and an app role with no post count
    // has nothing to allocate. Roles with 0 posts are kept and simply never
    // have room, so R16 shows up as demand that can never be met.
    Capacity  = Table.SelectRows(DimRole, each [JoinStatus] = "Matched"
                                            or [JoinStatus] = "Matched - but zero posts"),
    CapRec0   = Record.FromList(
                    List.Transform(Capacity[Posts], each Number.From(_ ?? 0)),
                    Capacity[RoleKey]),

    // ---------- one ordered choice list per person ----------
    // Records rather than bare keys, so the pick carries its true Rank rather
    // than a list position. Ranks are not guaranteed contiguous.
    Sorted    = Table.Sort(Preferences, {{"EmployeeID", Order.Ascending}, {"Rank", Order.Ascending}}),
    ByPerson  = Table.Group(Sorted, {"EmployeeID"}, {
                    {"Choices", each Table.ToRecords(
                                        Table.SelectColumns(
                                            Table.Sort(_, {{"Rank", Order.Ascending}}),
                                            {"RoleKey","Rank"})), type list},
                    {"RolesRanked", each Table.RowCount(_), Int64.Type}
                }),

    // ---------- deterministic shuffle ----------
    // Simple rolling hash over the bytes of the id, seeded. Not cryptographic;
    // it only needs to scatter people evenly and reproducibly.
    HashText  = (t as nullable text, seed as number) as number =>
        List.Accumulate(
            Binary.ToList(Text.ToBinary(Text.From(t ?? "") & "#" & Text.From(seed))),
            Number.Mod(seed * 2654435761, 2147483647),
            (s, b) => Number.Mod(s * 31 + b, 2147483647)
        ),
    WithHash  = Table.AddColumn(ByPerson, "ShuffleKey",
                    each HashText([EmployeeID], WhatIfSeed), type number),
    Shuffled  = Table.Sort(WithHash, {{"ShuffleKey", Order.Ascending}}),
    Queue     = Table.ToRecords(Shuffled),

    // Shared by both passes: the first choice in `opts` that still has a post.
    FirstFree = (rem as record, opts as list) as nullable record =>
        List.First(
            List.Select(opts, (c) =>
                c[RoleKey] <> null and c[RoleKey] <> ""
                and Record.FieldOrDefault(rem, c[RoleKey], 0) > 0),
            null),

    Take      = (rem as record, hit as nullable record) as record =>
        if hit = null then rem else Record.TransformFields(rem, {hit[RoleKey], each _ - 1}),

    // ---------- PASS 1 — justified choices only (ranks 1-3) ----------
    Pass1 = List.Accumulate(Queue, [Rem = CapRec0, Rows = {}], (st, p) =>
        let
            hit = FirstFree(st[Rem], List.Select(p[Choices], each _[Rank] <= 3)),
            row = p & [ AssignedRoleKey = if hit = null then null else hit[RoleKey],
                        OutcomeRank     = if hit = null then 0 else hit[Rank] ]
        in
            [Rem = Take(st[Rem], hit), Rows = st[Rows] & {row}]),

    // ---------- PASS 2 — fallback below the justification line ----------
    // Only the unplaced are reconsidered, and only against ranks 4+. Anyone
    // placed in pass 1 passes through untouched.
    Pass2 = List.Accumulate(Pass1[Rows], [Rem = Pass1[Rem], Rows = {}], (st, p) =>
        if p[OutcomeRank] <> 0 then [Rem = st[Rem], Rows = st[Rows] & {p}]
        else
            let
                hit = FirstFree(st[Rem], List.Select(p[Choices], each _[Rank] > 3)),
                row = p & [ AssignedRoleKey = if hit = null then null else hit[RoleKey],
                            OutcomeRank     = if hit = null then 0 else hit[Rank] ]
            in
                [Rem = Take(st[Rem], hit), Rows = st[Rows] & {row}]),

    // ---------- labels ----------
    Ordinal   = (n as number) as text =>
        let
            t2 = Number.Mod(n, 100), t1 = Number.Mod(n, 10),
            sfx = if t2 >= 11 and t2 <= 13 then "th"
                  else if t1 = 1 then "st" else if t1 = 2 then "nd"
                  else if t1 = 3 then "rd" else "th"
        in Text.From(n) & sfx,

    Raw       = Table.FromRecords(Pass2[Rows]),
    Banded    = Table.AddColumn(Raw, "OutcomeBand", each
                    if [OutcomeRank] = 0 then "Unplaceable"
                    else if [OutcomeRank] <= 3 then "Justified choice"
                    else "Below the justification line", type text),
    Labelled  = Table.AddColumn(Banded, "Outcome", each
                    if [OutcomeRank] = 0 then "Unplaceable"
                    else Ordinal([OutcomeRank]) & " choice", type text),

    // ---------- names for the page-4 table ----------
    // Pref1Name..Pref3Name come from PreferenceWide, which is where all role
    // name resolution lives. AssignedRoleKey needs its own lookup.
    JW        = Table.NestedJoin(Labelled, {"EmployeeID"}, PreferenceWide, {"EmployeeID"}, "W", JoinKind.LeftOuter),
    EW        = Table.ExpandTableColumn(JW, "W",
                    {"Pref1Name","Pref2Name","Pref3Name"},
                    {"Pref1Name","Pref2Name","Pref3Name"}),
    JA        = Table.NestedJoin(EW, {"AssignedRoleKey"}, DimRole, {"RoleKey"}, "DA", JoinKind.LeftOuter),
    EA        = Table.ExpandTableColumn(JA, "DA", {"RoleName"}, {"AssignedRoleNameRaw"}),
    // A null here is not a broken join: it means neither pass found a free post,
    // which is the whole point of the page. Say that rather than leaving a blank.
    LabelA    = Table.AddColumn(EA, "AssignedRoleName", each
                    if [AssignedRoleKey] = null then "Unplaceable"
                    else ([AssignedRoleNameRaw] ?? "(unknown role)"), type text),

    // Choices is a list column and cannot load into the model.
    Drop      = Table.RemoveColumns(LabelA, {"Choices","ShuffleKey","AssignedRoleNameRaw"}, MissingField.Ignore),
    Typed     = Table.TransformColumnTypes(Drop, {
                    {"EmployeeID", type text}, {"AssignedRoleKey", type text},
                    {"AssignedRoleName", type text}, {"OutcomeRank", Int64.Type},
                    {"OutcomeBand", type text}, {"Outcome", type text},
                    {"RolesRanked", Int64.Type},
                    {"Pref1Name", type text}, {"Pref2Name", type text}, {"Pref3Name", type text}
                })
in
    Typed


// ---- Query: WhatIfRoleFill  (per-role fill after the run) ------------------
// How full each role ended up, and how many posts nobody took. Restricted to
// ASSIGNABLE roles — the same set the allocation could draw on. Including the
// unkeyed capacity rows here would show three posts permanently unfilled and
// invite the reader to hunt for a bug that is really a data problem; page 6 is
// where those belong.
let
    Assigned = Table.Group(
                   Table.SelectRows(WhatIfAssignment, each [AssignedRoleKey] <> null),
                   {"AssignedRoleKey"}, {{"Filled", each Table.RowCount(_), Int64.Type}}),
    Base     = Table.SelectRows(DimRole, each [JoinStatus] = "Matched"
                                          or [JoinStatus] = "Matched - but zero posts"),
    Joined   = Table.NestedJoin(Base, {"RoleKey"}, Assigned, {"AssignedRoleKey"}, "A", JoinKind.LeftOuter),
    Exp      = Table.ExpandTableColumn(Joined, "A", {"Filled"}, {"Filled"}),
    Zeros    = Table.TransformColumns(Exp, {{"Filled", each _ ?? 0, Int64.Type}}),
    Unfilled = Table.AddColumn(Zeros, "PostsUnfilled", each [Posts] - [Filled], Int64.Type)
in
    Unfilled
