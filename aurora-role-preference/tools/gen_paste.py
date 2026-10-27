#!/usr/bin/env python3
"""
Generate paste/<screen>.controls.yaml from Src/<screen>.pa.yaml.

Power Apps Studio's Code View paste expects a TOP-LEVEL LIST OF CONTROLS on the
clipboard, not the `Screens:` document that .pa.yaml (pack/unpack) format uses.
This strips the wrapper and normalises the result to what the deserializer
accepts:

  Src/scrX.pa.yaml                     paste/scrX.controls.yaml
  --------------------------------     -------------------------------
  Screens:                             - conRoot:
    scrX:                                  Control: GroupContainer@1.5.0
      Properties:            ---->         ...
        Fill: =...                     - conSomeOverlay:
      Children:                            ...
        - conRoot:
            Control: ...

Three transformations, all required:

  1. Drop everything up to and including the screen's `Children:` line. Screen
     PROPERTIES (Fill, OnVisible) are NOT carried by a control paste - they must
     be set by hand in Studio. See paste/HOW-TO-PASTE.md.
  2. Dedent by 6 spaces so the first control sits at column 0.
  3. Strip `#` comments and blank lines. Studio's YAML parser rejects them with
     `PA1001 ... YamlInvalidSyntax`. The Src files keep their comments for Git.

It also writes paste/screens/<screen>.screen.yaml: the WHOLE screen - its own
properties (Fill, OnVisible) plus every control - in the same `Screens:` form
Studio shows under "View code" on a screen. Paste one of those onto the app in
the Tree view to replace a screen in one go, OnVisible included.

It also writes paste/admin-rebuild.powerfx: the admin data build, lifted
from btnRefreshOverview.OnSelect on scrOverview (btnRefreshSubs on
scrSubmissions carries the same text - tools/scan_paste.py checks). Use it
if either button's formula ever has to be re-pasted by hand.

And it writes paste/test-app/: a copy of every paste file that names the
Preferences or PreferenceResponses table, with those names suffixed _1. The
Phase 2 test app has each of those two tables bound twice and its formulas
use the _1 bindings, so the plain files show "name isn't valid" there.
Removing the duplicate data sources and re-adding each table once makes the
plain files work and this folder unnecessary.

And it writes paste/demo-app/: the DEMO MODE version of every paste file that
touches a Dataverse table (docs/demo-mode.md). Each table is swapped for an
in-memory collection of fictional data, the Refresh() calls go (a collection
cannot be refreshed), the confirmation email goes to the person signed in
only, and the OnStart gains a first section that builds the fictional data
(from tools/make_demo_data.py). A copy of the app pasted from that folder
reads and writes no table at all.

Usage:  python3 tools/gen_paste.py scrLanding
        python3 tools/gen_paste.py            # all screens
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "Src")
OUT = os.path.join(ROOT, "paste")

SCREENS = [
    "scrLanding", "scrForm", "scrDetail", "scrReview",
    "scrQuestions", "scrCompleted", "scrOverview", "scrSubmissions",
    # Phase 2 - role alignment accept/reject
    "scrAlignment", "scrRejection", "scrAlignLocked",
]


def block(name):
    lines = open(os.path.join(SRC, name + ".pa.yaml")).read().split("\n")
    out, started = [], False
    for ln in lines:
        if not started:
            # the screen's own `    Children:` - 4 spaces, not deeper
            if ln.startswith("    Children:") and not ln.startswith("     "):
                started = True
            continue
        s = ln.strip()
        if s == "" or s.startswith("#"):
            continue
        out.append(ln[6:] if ln.startswith("      ") else ln)
    return "\n".join(out).rstrip() + "\n"


SCREENS_OUT = os.path.join(OUT, "screens")


def screen_file(name):
    """The whole screen: Src with comments and blank lines removed, no dedent."""
    out, started = [], False
    for ln in open(os.path.join(SRC, name + ".pa.yaml")).read().split("\n"):
        if not started:
            if ln.startswith("Screens:"):
                started = True
            else:
                continue
        s = ln.strip()
        if s == "" or s.startswith("#"):
            continue
        out.append(ln)
    return "\n".join(out).rstrip() + "\n"


def onselect(screen, control):
    """The OnSelect formula of `control` on `screen`, dedented, '=' stripped."""
    lines = open(os.path.join(SRC, screen + ".pa.yaml")).read().split("\n")
    i = next(k for k, ln in enumerate(lines) if ln.strip() == "- %s:" % control)
    j = next(k for k in range(i, len(lines)) if lines[k].strip().startswith("OnSelect:"))
    if lines[j].strip() != "OnSelect: |-":
        return lines[j].split("OnSelect: =", 1)[1]
    base = len(lines[j + 1]) - len(lines[j + 1].lstrip())
    out = []
    for ln in lines[j + 1:]:
        if ln.strip() and len(ln) - len(ln.lstrip()) < base:
            break
        out.append(ln[base:])
    return "\n".join(out).rstrip()[1:]


ADMIN_REBUILD_HEADER = """/* =============================================================================
   ADMIN DATA BUILD  (GENERATED by tools/gen_paste.py - edit Src, not this file)
   The OnSelect of btnRefreshOverview (scrOverview) and btnRefreshSubs
   (scrSubmissions). Both buttons carry exactly this text; each screen's
   OnVisible presses its button with Select(). Leading '=' already removed.

   Admins get everyone with an aligned role on Alignments; a line manager
   only the Alignments rows whose LineManagerEmail is their own (lower-case)
   address. People with no Alignments row are left out.
   ============================================================================ */
"""


TEST_APP = os.path.join(OUT, "test-app")
SUFFIX = {
    "'RolePreference PreferenceResponses'": "'RolePreference PreferenceResponses_1'",
    "'RolePreference Preferences'": "'RolePreference Preferences_1'",
}
# Phase 1 is retired; its frozen OnStart is not needed in the test app.
TEST_APP_SKIP = {"App_OnStart.phase1.powerfx"}


def to_test_app(text):
    for old, new in SUFFIX.items():
        text = text.replace(old, new)
    return text


def write_test_app():
    os.makedirs(TEST_APP, exist_ok=True)
    for f in os.listdir(TEST_APP):
        os.remove(os.path.join(TEST_APP, f))
    made = []
    sources = [os.path.join(OUT, f) for f in sorted(os.listdir(OUT))]
    sources += [os.path.join(SCREENS_OUT, f) for f in sorted(os.listdir(SCREENS_OUT))]
    for path in sources:
        f = os.path.basename(path)
        if f in TEST_APP_SKIP or not os.path.isfile(path):
            continue
        if not (f.endswith(".controls.yaml") or f.endswith(".screen.yaml") or f.endswith(".powerfx")):
            continue
        text = open(path).read()
        if not any(old in text for old in SUFFIX):
            continue
        with open(os.path.join(TEST_APP, f), "w") as fh:
            fh.write(to_test_app(text))
        made.append(f)
    rows = "\n".join(
        f"| `{f}` | `../{'screens/' if f.endswith('.screen.yaml') else ''}{f}` |" for f in made
    )
    readme = f"""# Paste files for the Phase 2 TEST app (`_1` table names)

GENERATED by `tools/gen_paste.py` - do not edit; edit `Src/` or the file in
`paste/`, then regenerate.

The test app has `RolePreference Preferences` and `RolePreference
PreferenceResponses` bound twice, and its formulas use the `_1` bindings
(`'RolePreference Preferences_1'`, `'RolePreference PreferenceResponses_1'`),
which carry the current schema. The plain files in `paste/` use the names
without `_1`, so in the test app they show *"Name isn't valid"*.

**Use the file from this folder when it exists; otherwise use the one in
`paste/` as it is** - every other file names neither table, so it is the same
in both apps. People, Roles, Eligibilities and Alignments are never suffixed.

| This folder | Same as, with `_1` names |
|---|---|
{rows}

Copy from GitHub (open the file, then **Copy raw file**), not from a chat
window - a partial copy pastes a half-empty screen with no error.

To retire this folder: in the test app remove BOTH data-source entries for each
of the two tables and add each table back once. The plain files then work.
"""
    with open(os.path.join(TEST_APP, "README.md"), "w") as fh:
        fh.write(readme)
    print(f"wrote test-app/ ({len(made)} files)")


DEMO_APP = os.path.join(OUT, "demo-app")
# Longest names first is not needed - the closing quote keeps them distinct.
DEMO_TABLES = {
    "'RolePreference PreferenceResponses_1'": "colDemoResponses",
    "'RolePreference PreferenceResponses'": "colDemoResponses",
    "'RolePreference Preferences_1'": "colDemoPreferences",
    "'RolePreference Preferences'": "colDemoPreferences",
    "'RolePreference People'": "colDemoPeople",
    "'RolePreference Roles'": "colDemoRoles",
    "'RolePreference Eligibilities'": "colDemoEligibilities",
    "'RolePreference Alignments'": "colDemoAlignments",
}
# Refresh() takes a data source; on a collection it does not bind. Each call
# goes with the line break and indent after it, so a first line reading
# "=Refresh(...);" becomes "=" + the next statement.
DEMO_REFRESH = re.compile(r"Refresh\('RolePreference [A-Za-z]+(?:_1)?'\);\n[ \t]*")
# The confirmation email: to the person signed in only - no Aurora mailbox,
# no line manager - so a demo never mails anyone but the presenter.
DEMO_CC = (
    '{Cc: "aurora@environment-agency.gov.uk" & If(IsBlank(varAlignLmEmail), "", ";" & varAlignLmEmail), Importance: "Normal"}',
    '{Importance: "Normal"}',
)
# Formula-bar files the demo copy needs, besides every screen that names a table.
DEMO_FORMULAS = {
    "App_OnStart.dataverse.powerfx": "App_OnStart.demo.powerfx",
    "admin-rebuild.powerfx": "admin-rebuild.powerfx",
    "scrOverview_OnVisible.powerfx": "scrOverview_OnVisible.powerfx",
    "scrSubmissions_OnVisible.powerfx": "scrSubmissions_OnVisible.powerfx",
}
DEMO_ONSTART_HEADER = """/* =============================================================================
   AURORA - DEMO OnStart (formula-bar paste; leading '=' already removed)
   FOR THE DEMO COPY OF THE APP ONLY - docs/demo-mode.md. GENERATED by
   tools/gen_paste.py from paste/App_OnStart.dataverse.powerfx and
   tools/make_demo_data.py; edit those and regenerate, not this file.
   Reads no Dataverse table: the first section builds fictional data in
   collections, and the rest is the live OnStart with every table swapped for
   its collection.
   COLUMN-NAME NOTE: Split() returns a column called Value in current Power Fx.
   If the formula bar flags .Value, replace those .Value with .Result.
   ============================================================================ */
"""


def to_demo_app(text):
    text = DEMO_REFRESH.sub("", text)
    for old, new in DEMO_TABLES.items():
        text = text.replace(old, new)
    return text.replace(*DEMO_CC)


def demo_app_text(source_name, text):
    """The demo-app version of a paste file, by its name in paste/."""
    if source_name != "App_OnStart.dataverse.powerfx":
        return to_demo_app(text)
    if text.startswith("/*"):  # the Dataverse prerequisites header no longer applies
        text = text[text.index("*/") + 2:].lstrip("\n")
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from make_demo_data import powerfx_demo_block
    return DEMO_ONSTART_HEADER + powerfx_demo_block() + "\n" + to_demo_app(text)


def demo_app_sources():
    """(name in paste/, name in demo-app/) for every file the demo copy needs."""
    pairs = []
    for f in sorted(os.listdir(OUT)):
        path = os.path.join(OUT, f)
        if not os.path.isfile(path):
            continue
        if f.endswith(".controls.yaml"):
            text = open(path).read()
            if any(t in text for t in DEMO_TABLES) or DEMO_CC[0] in text:
                pairs.append((f, f))
        elif f in DEMO_FORMULAS:
            pairs.append((f, DEMO_FORMULAS[f]))
    return pairs


def write_demo_app():
    os.makedirs(DEMO_APP, exist_ok=True)
    for f in os.listdir(DEMO_APP):
        os.remove(os.path.join(DEMO_APP, f))
    pairs = demo_app_sources()
    for src, dst in pairs:
        with open(os.path.join(DEMO_APP, dst), "w") as fh:
            fh.write(demo_app_text(src, open(os.path.join(OUT, src)).read()))
    screens = [d for _, d in pairs if d.endswith(".controls.yaml")]
    rows = "\n".join(f"| `{d}` | {'App > OnStart' if d.startswith('App_OnStart') else ('screen ' + d.split('_')[0] + ' > OnVisible' if 'OnVisible' in d else ('btnRefreshOverview and btnRefreshSubs > OnSelect (already inside the two screens below)' if d.startswith('admin-rebuild') else 'paste over the screen ' + d.split('.')[0] + ' (replace its controls)'))} |" for _, d in pairs)
    readme = f"""# Paste files for the DEMO copy of the app (fictional data, no Dataverse)

GENERATED by `tools/gen_paste.py` - do not edit; edit `Src/`, the file in
`paste/`, or `tools/make_demo_data.py`, then regenerate.

**Only ever paste these into the demo copy, never into the live app.** Every
Dataverse table is replaced by an in-memory collection of fictional data, so a
copy built from these files reads and writes no real data. Full steps:
[`docs/demo-mode.md`](../../docs/demo-mode.md).

| File | Where it goes |
|---|---|
{rows}

The other {len(SCREENS) - len(screens)} screens name no table and need nothing.
When everything is pasted, **remove every RolePreference table from the copy's
Data pane**: anything still pointing at one then shows an error instead of
quietly reading real data.

Copy from GitHub (open the file, then **Copy raw file**), not from a chat
window - a partial copy pastes a half-empty screen with no error.
"""
    with open(os.path.join(DEMO_APP, "README.md"), "w") as fh:
        fh.write(readme)
    print(f"wrote demo-app/ ({len(pairs)} files)")


def main():
    names = sys.argv[1:] or SCREENS
    for name in names:
        text = block(name)
        with open(os.path.join(OUT, name + ".controls.yaml"), "w") as fh:
            fh.write(text)
        print(f"wrote {name}.controls.yaml ({len(text)} bytes)")
    os.makedirs(SCREENS_OUT, exist_ok=True)
    for name in names:
        with open(os.path.join(SCREENS_OUT, name + ".screen.yaml"), "w") as fh:
            fh.write(screen_file(name))
    print(f"wrote screens/ ({len(names)} whole-screen files)")
    text = ADMIN_REBUILD_HEADER + onselect("scrOverview", "btnRefreshOverview") + "\n"
    with open(os.path.join(OUT, "admin-rebuild.powerfx"), "w") as fh:
        fh.write(text)
    print(f"wrote admin-rebuild.powerfx ({len(text)} bytes)")
    write_test_app()
    write_demo_app()


if __name__ == "__main__":
    main()
