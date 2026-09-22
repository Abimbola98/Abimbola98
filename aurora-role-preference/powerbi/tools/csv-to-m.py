#!/usr/bin/env python3
"""Regenerate queries/00-capacity-data.m from data/roles_capacity.csv.

The capacity numbers are embedded in M rather than read from a file. The CSV
stays the source of truth and this script carries it across, so nobody edits
9KB of M by hand. Run it after any change to the CSV:

    python3 tools/csv-to-m.py

Why embedded at all: the report is built on a VM, and a CSV on a local path
needs an on-premises gateway to refresh in the Service and only ever works from
one machine. Embedding removes the file, the path and the gateway. The cost is
that updating post counts becomes a Desktop edit and republish rather than a
spreadsheet edit -- see README section 3.
"""
import io, os, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(HERE, "data", "roles_capacity.csv")
DST  = os.path.join(HERE, "queries", "00-capacity-data.m")

def m_literal(line):
    """A CSV line as an M text literal. M escapes " as "" and # as #(#)."""
    return '"' + line.replace('#', '#(#)').replace('"', '""') + '"'

def main():
    raw = io.open(SRC, encoding="utf-8").read()
    if "–" in raw or "—" in raw:
        sys.exit("CSV still contains en/em dashes -- normalise them first.")
    lines = [l for l in raw.replace("\r\n", "\n").split("\n") if l != ""]
    body  = ",\n        ".join(m_literal(l) for l in lines)

    out = HEADER + "let\n    Lines = {\n        " + body + "\n    }\nin\n    Text.Combine(Lines, \"#(lf)\")\n"
    io.open(DST, "w", encoding="utf-8", newline="\n").write(out)
    print("wrote %s (%d rows incl header, %d chars)" % (DST, len(lines), len(out)))

HEADER = """// =============================================================================
// Capacity data, embedded  (Power Query / M)
// =============================================================================
// GENERATED FILE -- do not edit by hand.
// Source: powerbi/data/roles_capacity.csv
// Regenerate: python3 powerbi/tools/csv-to-m.py
//
// The post counts live here as text rather than in a file the report has to
// find. That is deliberate: this report is assembled on a VM, and a CSV on a
// local path needs an on-premises data gateway to refresh in the Service and
// only ever works from the machine holding it. Embedded, the model refreshes in
// the Service on the Dataverse credential alone -- no gateway, no file share,
// no path to break.
//
// The cost, and it is a real one: changing a post count is now a Power BI
// Desktop edit and a republish, not a spreadsheet edit. Whoever owns the
// numbers cannot maintain them without Desktop. If that becomes the binding
// constraint, README section 3 has the two ways out -- put the CSV on
// SharePoint, or add a Posts column to the Roles table in Dataverse.
//
// This is still conceptually the SECOND SOURCE. It carries post counts and
// nothing else, it joins to Dataverse on RoleKey, and DimRole still full-outer
// merges the two so a key on one side and not the other stays visible.
//
// ---- Query: CapacityText  (staging -- right-click > Disable Load) -----------
// =============================================================================

"""

if __name__ == "__main__":
    main()
