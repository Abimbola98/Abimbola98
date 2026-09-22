#!/usr/bin/env python3
"""Regenerate measures-queryview.dax from measures.dax.

Power BI Desktop's formula bar takes one measure at a time, and Tabular Editor
cannot always be installed -- a locked-down VM, for instance. Desktop's DAX
query view accepts a DEFINE block instead, and offers an "Update model: Add new
measure" action against each MEASURE in it, so all of them live in one editable
buffer rather than sixty-odd separate paste cycles.

measures.dax stays the source of truth. Run this after changing it:

    python3 tools/dax-to-queryview.py
"""
import io, os, re, sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC  = os.path.join(HERE, "measures.dax")
DST  = os.path.join(HERE, "measures-queryview.dax")

START = re.compile(r'^([A-Za-z][A-Za-z0-9 ]*?)\s*=(.*)$')

# A line that looks like the start of a measure but that START will not match:
# a name with a character outside [A-Za-z0-9 ], most often a bracket. Such a
# line used to be swallowed into the PREVIOUS measure's expression, and the run
# still reported success -- the measure simply never appeared in the output and
# the one above it silently gained a second expression. Caught in anger by a
# measure named "Roles Offered (bypass)": the count stayed the same across a
# run that had just added two.
# Not indented, not a continuation, and the text before the "=" is name-shaped:
# no bracket, comma or quote (those mean the "=" is inside an expression), and
# not an ALL-CAPS function call such as CALCULATE ( ... ) or IF ( ... ).
SUSPECT = re.compile(r'^(?!VAR |RETURN )(?![A-Z]{2,}\s*\()([A-Za-z][^=\n\[,"]{0,80})=(?!=)')

def parse(text):
    """Yield (name, expression) in file order, dropping comments.

    Raises on a line that looks like a measure definition but whose name this
    parser cannot read, rather than absorbing it into the measure above.
    """
    lines = [l for l in text.split("\n") if not l.lstrip().startswith("//")]
    out, name, buf, bad = [], None, [], []
    for line in lines:
        if line and not line.startswith(" ") and not START.match(line) \
                and SUSPECT.match(line):
            bad.append(line.strip())
        m = START.match(line)
        if m and not line.startswith(("VAR", "RETURN")):
            if name:
                out.append((name, "\n".join(buf).strip()))
            name, buf = m.group(1).strip(), [m.group(2)]
        elif name is not None:
            buf.append(line)
    if name:
        out.append((name, "\n".join(buf).strip()))
    seen = {}
    for n, _ in out:
        seen[n] = seen.get(n, 0) + 1
    dupes = sorted(n for n, k in seen.items() if k > 1)
    if dupes:
        raise SystemExit(
            "measures.dax: the same measure name is defined more than once.\n"
            "A model holds one measure per name, so the second paste silently "
            "fails or overwrites the first:\n  " + "\n  ".join(dupes))
    if bad:
        raise SystemExit(
            "measures.dax: these look like measure definitions but the name "
            "could not be read.\nMeasure names here must be letters, digits "
            "and spaces only -- no brackets or punctuation:\n  "
            + "\n  ".join(bad))
    return out

def main():
    measures = parse(io.open(SRC, encoding="utf-8").read())
    if not measures:
        sys.exit("no measures parsed from measures.dax")
    body = []
    for name, expr in measures:
        indented = "\n".join(("        " + l).rstrip() for l in expr.split("\n"))
        body.append("    MEASURE _Measures[%s] =\n%s" % (name, indented))
    out = HEADER + "DEFINE\n\n" + "\n\n".join(body) + "\n\nEVALUATE\n    { 1 }\n"
    io.open(DST, "w", encoding="utf-8", newline="\n").write(out)
    print("wrote %s (%d measures)" % (DST, len(measures)))

HEADER = """// =============================================================================
// Every measure, as one DAX query-view DEFINE block
// =============================================================================
// GENERATED FILE -- do not edit by hand.
// Source: powerbi/measures.dax     Regenerate: python3 powerbi/tools/dax-to-queryview.py
//
// For adding the measures without Tabular Editor. Paste the whole thing into
// Power BI Desktop's DAX QUERY VIEW (the DAX icon in the left rail), and use the
// "Update model: Add new measure" action that appears above each MEASURE line.
// _Measures must already exist as a table.
//
// Work DOWNWARDS. Later measures reference earlier ones by name, and a measure
// cannot be added to the model before the ones it calls.
//
// This file carries no comments -- measures.dax has the reasoning, and this one
// exists only to be pasted.
// =============================================================================

"""

if __name__ == "__main__":
    main()
