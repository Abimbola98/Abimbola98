// =============================================================================
// What-if: capacitated random assignment  (Power Query / M)
// =============================================================================
// "If we randomly assign everyone their top choice, how many get their 1st,
// how many drop to 2nd or 3rd?"
//
// This is a CAPACITATED assignment, not a simple count. Giving everyone their
// first choice is impossible where a role has fewer posts than takers, so the
// model has to allocate in some order and let capacity run out. Two consequences
// worth stating to Kate before she reads the numbers:
//
//   * The ORDER decides who wins. A person early in the shuffle takes the last
//     post on a contested role and everyone after them drops to their 2nd. So a
//     single run tells you the SHAPE (roughly what proportion get their 1st),
//     not who gets what. Nobody's individual row here is a decision.
//   * Only the top three are modelled, because only three are collected. Anyone
//     whose three choices are all full comes out "Unassigned" — that is a real
//     signal about oversubscription, not a bug.
//
// Why Power Query and not DAX: allocation is sequential — each person changes
// the capacity the next person sees. DAX has no clean way to carry that state
// down a table. List.Accumulate does exactly this.
//
// Determinism: Number.Random() would give a different answer on every refresh
// and break any conversation about the numbers. Instead the order comes from a
// hash of EmployeeID mixed with WhatIfSeed, so the same seed always reproduces
// the same run, and changing the seed gives an independent one. Run it at a few
// seeds to see how stable the headline percentages are.
// =============================================================================


// ---- Query: WhatIfSeed  (parameter) ----------------------------------------
// Manage Parameters > New > Decimal/Whole number. Change it to re-roll.
1


// ---- Query: WhatIfAssignment -----------------------------------------------
let
    // ---------- inputs ----------
    People3   = PreferenceWide,
    Capacity  = Table.SelectRows(RolesCapacity, each [HasKey] = true),

    // Capacity as a record keyed by RoleKey, so a lookup and a decrement are
    // both O(1) inside the fold. Roles with 0 posts are included and simply
    // never have room.
    CapKeys   = Capacity[RoleKey],
    CapVals   = List.Transform(Capacity[Posts], each Number.From(_ ?? 0)),
    CapRec0   = Record.FromList(CapVals, CapKeys),

    // ---------- deterministic shuffle ----------
    // Simple rolling hash over the bytes of the id, seeded. Not cryptographic;
    // it only needs to scatter people evenly and reproducibly.
    HashText  = (t as nullable text, seed as number) as number =>
        List.Accumulate(
            Binary.ToList(Text.ToBinary(Text.From(t ?? "") & "#" & Text.From(seed))),
            Number.Mod(seed * 2654435761, 2147483647),
            (s, b) => Number.Mod(s * 31 + b, 2147483647)
        ),

    WithHash  = Table.AddColumn(People3, "ShuffleKey",
                    each HashText([EmployeeID], WhatIfSeed), type number),
    Shuffled  = Table.Sort(WithHash, {{"ShuffleKey", Order.Ascending}}),
    AsRecords = Table.ToRecords(Shuffled),

    // ---------- greedy allocation ----------
    // Walk the shuffled list once. Take the highest preference that still has a
    // post free; if all three are full, the person is Unassigned.
    Final = List.Accumulate(
        AsRecords,
        [Remaining = CapRec0, Rows = {}],
        (state, person) =>
            let
                rem  = state[Remaining],
                Free = (k as nullable text) as logical =>
                           k <> null and k <> "" and Record.FieldOrDefault(rem, k, 0) > 0,
                p1   = person[Pref1], p2 = person[Pref2], p3 = person[Pref3],
                pick = if Free(p1) then p1 else if Free(p2) then p2 else if Free(p3) then p3 else null,
                rank = if pick = null then 0 else if pick = p1 then 1 else if pick = p2 then 2 else 3,
                out  = if rank = 0 then "Unassigned" else Text.From(rank)
                           & (if rank = 1 then "st" else if rank = 2 then "nd" else "rd")
                           & " choice",
                newR = if pick = null then rem
                       else Record.TransformFields(rem, {pick, each _ - 1}),
                row  = person & [AssignedRoleKey = pick, OutcomeRank = rank, Outcome = out]
            in
                [Remaining = newR, Rows = state[Rows] & {row}]
    ),

    // ---------- output ----------
    Out       = Table.FromRecords(Final[Rows]),
    Typed     = Table.TransformColumnTypes(Out, {
                    {"EmployeeID", type text}, {"Pref1", type text},
                    {"Pref2", type text}, {"Pref3", type text},
                    {"AssignedRoleKey", type text},
                    {"OutcomeRank", Int64.Type}, {"Outcome", type text}
                }),
    Dropped   = Table.RemoveColumns(Typed, {"ShuffleKey"}, MissingField.Ignore)
in
    Dropped


// ---- Query: WhatIfRoleFill  (per-role fill after the run) ------------------
// How full each role ended up, and how many people wanted it but missed out.
// This is the honest "over/under subscribed" view: demand against posts.
let
    Assigned = Table.Group(
                   Table.SelectRows(WhatIfAssignment, each [AssignedRoleKey] <> null),
                   {"AssignedRoleKey"}, {{"Filled", each Table.RowCount(_), Int64.Type}}),
    Base     = Table.SelectRows(RolesCapacity, each [HasKey] = true),
    Joined   = Table.NestedJoin(Base, {"RoleKey"}, Assigned, {"AssignedRoleKey"}, "A", JoinKind.LeftOuter),
    Exp      = Table.ExpandTableColumn(Joined, "A", {"Filled"}, {"Filled"}),
    Zeros    = Table.TransformColumns(Exp, {{"Filled", each _ ?? 0, Int64.Type}}),
    Unfilled = Table.AddColumn(Zeros, "PostsUnfilled", each [Posts] - [Filled], Int64.Type)
in
    Unfilled
