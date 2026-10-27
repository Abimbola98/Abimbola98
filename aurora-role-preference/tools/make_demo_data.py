#!/usr/bin/env python3
"""Build a fictional data set for a DEMO copy of the Aurora Role Preference app.

Writes one import file per Dataverse table, headers matching the display names
the app uses, ready for Tables > Import > Import data from Excel in a SEPARATE
demo environment (docs/demo-environment.md says why it must be separate):

    RolePreference_Roles_DEMO.xlsx                 16 fictional roles
    RolePreference_People_DEMO.xlsx                36 fictional staff (+ presenters)
    RolePreference_Eligibilities_DEMO.xlsx         who may rank which role
    RolePreference_Preferences_DEMO.xlsx           Stage 1 rankings
    RolePreference_PreferenceResponses_DEMO.xlsx   Stage 2 answers (top three)
    RolePreference_Alignments_DEMO.xlsx            Stage 3: accepted / rejected / awaiting

Everything is invented. Staff emails use example.com, a domain reserved for
examples, so nothing can ever reach a real mailbox. Employee numbers start at
900101, outside the real range.

PRESENTERS. Whoever runs the demo must be in People with their real sign-in
address, or the app cannot find them. Those details are real staff data, so
they are NOT in this file: pass them in a CSV (Name,EmployeeID,Email - plus
optional Grade,Area,Team) that is kept out of the repository:

    python3 tools/make_demo_data.py --out DIR --presenters presenters.csv

Each presenter is an admin, may rank five roles, has NOT filled in the form
(so the form can be shown live) and has an aligned role waiting for a
response. The first presenter is also named as line manager on five fictional
staff, so the line-manager view can be shown by switching their IsAdmin off.

The output is deterministic for a given --seed.
"""

import argparse
import csv
import datetime as dt
import os
import random
import re
import sys

try:
    import openpyxl
    from openpyxl.styles import Font
except ImportError:  # pragma: no cover
    sys.exit("openpyxl is required: pip install openpyxl")


# ---------------------------------------------------------------------------
# Reference data. Every text field on Roles is kept to 100 characters or
# fewer, the Dataverse default for a text column, so the import cannot fail
# on length whatever the demo tables were sized to.
# ---------------------------------------------------------------------------

REGIONS = ["North East", "North West", "Midlands", "East", "South East", "South West"]
REGION_GROUP = {
    "North East": "North", "North West": "North", "Midlands": "Midlands",
    "East": "East", "South East": "South", "South West": "South",
}
TEAMS = [
    "Programme Delivery", "Asset Performance", "Partnerships & Funding",
    "Data & Insight", "Business Support", "Project Assurance",
]

# key, name, grade, family, regions it serves (None = anywhere), default option
ROLES = [
    ("R01", "Officer - Programme Office - North", "SG4", "Programme Office", {"North"}, False),
    ("R02", "Officer - Programme Office - South", "SG4", "Programme Office", {"South"}, False),
    ("R03", "Officer - Insight & Reporting", "SG4", "Insight & Reporting", None, True),
    ("R04", "Officer - Delivery Hub - Midlands & East", "SG4", "Delivery Hub", {"Midlands", "East"}, False),
    ("R05", "Advisor - Programme Office - North", "SG5", "Programme Office", {"North"}, True),
    ("R06", "Advisor - Programme Office - South", "SG5", "Programme Office", {"South"}, True),
    ("R07", "Advisor - Delivery Hub - Midlands", "SG5", "Delivery Hub", {"Midlands"}, True),
    ("R08", "Advisor - Delivery Hub - East", "SG5", "Delivery Hub", {"East"}, True),
    ("R09", "Advisor - Insight & Reporting - Performance", "SG5", "Insight & Reporting", None, True),
    ("R10", "Advisor - Partnerships - Funding & Investment", "SG5", "Partnerships", None, True),
    ("R11", "Advisor - Risk & Assurance", "SG5", "Risk & Assurance", None, True),
    ("R12", "Team Leader - Programme Office - North", "SG6", "Programme Office", {"North"}, False),
    ("R13", "Team Leader - Programme Office - South", "SG6", "Programme Office", {"South"}, False),
    ("R14", "Senior Advisor - Insight & Reporting - Benefits", "SG6", "Insight & Reporting", None, False),
    ("R15", "Senior Advisor - Risk & Assurance", "SG6", "Risk & Assurance", None, False),
    ("R16", "Team Leader - Delivery Hub - Midlands & East", "SG6", "Delivery Hub", {"Midlands", "East"}, False),
]

FAMILY_TEXT = {
    "Programme Office": dict(
        short="Plans, tracks and reports progress across the programme.",
        purpose="Keeps the programme on track through good planning, governance and reporting.",
        resp=["Keep the plan current", "Prepare board papers",
              "Track actions and decisions", "Write progress reports"],
        req=["Experience of planning or reporting", "Clear written communication",
             "Confident with spreadsheets"],
        work="planning, governance and reporting",
        tasks=["keeping the programme plan up to date", "preparing board papers",
               "tracking actions and decisions", "pulling together the monthly progress report"],
        people="programme managers and senior responsible owners"),
    "Delivery Hub": dict(
        short="Helps schemes get delivered on time and on budget.",
        purpose="Supports project teams to deliver schemes safely, on time and on budget.",
        resp=["Track milestones and spend", "Manage contractor performance",
              "Resolve issues early", "Coordinate handovers"],
        req=["Experience of project delivery", "Good stakeholder skills",
             "Understanding of contracts"],
        work="project delivery",
        tasks=["tracking scheme milestones", "managing contractor performance",
               "resolving delivery issues", "coordinating handovers to operations"],
        people="project managers and our delivery partners"),
    "Insight & Reporting": dict(
        short="Turns programme data into clear reporting and insight.",
        purpose="Gives decision makers accurate, timely information about programme performance.",
        resp=["Build and run dashboards", "Improve data quality",
              "Analyse performance trends", "Report benefits"],
        req=["Strong analytical skills", "Excel or Power BI experience",
             "Able to explain data simply"],
        work="data and reporting",
        tasks=["building dashboards", "checking data quality",
               "analysing performance trends", "reporting the benefits we deliver"],
        people="analysts and the managers who rely on our reports"),
    "Partnerships": dict(
        short="Works with partners to secure funding for schemes.",
        purpose="Grows partnership funding so more schemes can go ahead.",
        resp=["Build cases for contributions", "Work with local authorities",
              "Track partner funding", "Prepare bids"],
        req=["Experience of partnership working", "Persuasive writing",
             "Knowledge of funding rules"],
        work="partnership funding",
        tasks=["building cases for partner contributions", "working with local authorities",
               "tracking partnership funding", "preparing funding bids"],
        people="local authorities and other funding partners"),
    "Risk & Assurance": dict(
        short="Makes sure programme risks are understood and managed.",
        purpose="Gives the programme confidence that risks are identified and managed well.",
        resp=["Maintain the risk register", "Run assurance reviews",
              "Follow up audit actions", "Facilitate workshops"],
        req=["Experience of risk management", "Attention to detail",
             "Confident challenging others"],
        work="risk and assurance",
        tasks=["maintaining the risk register", "running assurance reviews",
               "following up audit actions", "facilitating risk workshops"],
        people="project teams and the assurance board"),
}
GRADE_CONTEXT = {
    "SG4": "SG4 - Officer. Delivers tasks with support and guidance from the team.",
    "SG5": "SG5 - Advisor. Works independently and leads pieces of work.",
    "SG6": "SG6 - Senior Advisor or Team Leader. Leads people or a specialist area.",
}

# Which roles suit which current team (adds weight when ranking).
TEAM_FIT = {
    "Programme Delivery": {"Delivery Hub"},
    "Asset Performance": {"Delivery Hub"},
    "Partnerships & Funding": {"Partnerships"},
    "Data & Insight": {"Insight & Reporting"},
    "Business Support": {"Programme Office"},
    "Project Assurance": {"Risk & Assurance"},
}
TEAM_WORK = {
    "Programme Delivery": "coordinate delivery plans for a portfolio of capital schemes",
    "Asset Performance": "track asset inspections and the maintenance programme",
    "Partnerships & Funding": "help local partners put together contributions for new schemes",
    "Data & Insight": "produce the monthly performance reports and dashboards",
    "Business Support": "run governance and board support for our area",
    "Project Assurance": "carry out project reviews and look after the risk register",
}

# Fictional staff. Checked against nothing real here - see docs: if a name
# happens to match someone in your organisation, change it before the demo.
STAFF_NAMES = [
    "Amira Hassan", "Ben Whitlock", "Chloe Ndlovu", "Dev Malhotra", "Eleanor Fairweather",
    "Felix Brannigan", "Grace Adeyemi", "Hamish Rowntree", "Isla Petrovic", "Jamal Osei",
    "Kirsty Lindqvist", "Liam Hartnell", "Maya Desai", "Noah Penrose", "Olivia Kerrigan",
    "Priya Nair", "Quentin Ashby", "Rosa Delgado", "Samuel Achterberg", "Tanya Volkova",
    "Usman Qureshi", "Victoria Langdale", "William Ferrars", "Yasmin El-Amin", "Zoe Carmichael",
    "Aidan McGarry", "Callum Featherstone", "Daisy Ormerod", "Ethan Blackwood", "Fatima Begum",
    "George Tennant", "Hannah Okonjo", "Imran Siddiqui", "Jessica Thornbury", "Kofi Mensah",
    "Lucy Abernethy",
]
LINE_MANAGERS = [
    "jordan.ellis@example.com", "harriet.moss@example.com", "tom.akintola@example.com",
    "gwen.lloyd-jones@example.com", "sanjay.mehta@example.com", "ruth.inglis@example.com",
]

Q1_START = "Please provide a brief explanation as to why you have selected this role as your "
Q1_END = (" preference. For example; do you think this role aligns best with the activities you"
          " currently undertake? Will this role make the best use of your existing relationships?"
          " Do you think this role will align best with a specific area of interest e.g. Carbon?"
          " Any information provided will be used to inform the outcome of this process where possible.")
Q2 = ("Please use this space to provide any additional information on skills, experience or"
      " qualifications relevant to this role that you would like us to be aware of. Any information"
      " provided will be used to inform the outcome of this process where possible.")
ORDINAL = {1: "first", 2: "second", 3: "third"}

INTERESTS = ["carbon reduction", "nature-based solutions", "digital ways of working",
             "making better use of data", "working with communities",
             "developing junior colleagues", "value for money"]
QUALS = ["PRINCE2 Practitioner", "APM Project Fundamentals Qualification", "MSP Foundation",
         "Power BI Data Analyst certificate", "NEC4 Project Manager accreditation",
         "CMI Level 5 in Management and Leadership", "Lean Six Sigma Green Belt",
         "IOSH Managing Safely", "Agile Project Management Foundation"]
EXTRAS = ["I also mentor two apprentices in the team.",
          "Last year I moved our area reporting onto a shared dashboard.",
          "I sit on the regional health and safety forum.",
          "I have covered the team leader role twice in the last year.",
          "I am currently studying for a project management degree apprenticeship.",
          "In 2025 I chaired our area's improvement working group.",
          "I volunteer as a first aider and fire warden.",
          "I helped set up the new starter induction for our team."]

REJECTIONS = [
    ("Failure to follow our processes",
     "I do not feel my supporting answers were taken into account. I explained my experience in"
     " detail, but I have been aligned to a role I ranked near the bottom of my list."
     " I would like to understand how my answers were used when roles were allocated, and whether"
     " my first or second preference was considered before this decision was made."),
    ("Failure to follow our processes",
     "The aligned role would change where and how I work quite significantly, and I was not asked"
     " about this before the decision was made. I understood that this would be considered. I would"
     " welcome a conversation about whether a role closer to my current work could be offered."),
    ("Failure to follow our processes",
     "My current job uses skills that I described in detail in my answers, and the aligned role"
     " does not use them. I am concerned the process did not compare my experience against my top"
     " three roles as the guidance said it would."),
    ("Failure to follow our processes",
     "I was told preferences would be balanced against the number of posts available, but I have not"
     " been given any information about how that was done. I would like to see how the decision for"
     " my role was reached and whether the same approach was applied to everyone at my grade."),
    ("Failure to follow our processes",
     "I accept that not everyone can have their first choice, but this role is a step away from the"
     " work I have done for the last six years. I asked for my qualifications to be considered and"
     " I do not think they were. I would like my alignment reviewed against my second preference."),
]
DRAFT_REJECTION = (
    "Failure to follow our processes",
    "I would like to understand how my preferences were used. I am still talking this through with"
    " my line manager and will add more detail before I submit.")


# ---------------------------------------------------------------------------

def email_for(name):
    first, last = name.split(" ", 1)
    clean = lambda s: re.sub(r"[^a-z-]", "", s.lower().replace(" ", ""))
    return f"{clean(first)}.{clean(last)}@example.com"


def working_time(rng, start, days):
    d = start + dt.timedelta(days=rng.randrange(days))
    while d.weekday() >= 5:
        d += dt.timedelta(days=1)
    return d.replace(hour=rng.randint(8, 16), minute=rng.randrange(60), second=0)


def why_answer(rng, person, role, rank):
    fam = FAMILY_TEXT[role["family"]]
    t1, t2 = rng.sample(fam["tasks"], 2)
    openers = {
        1: [f"This is my first choice because it is closest to what I already do. I currently"
            f" {TEAM_WORK[person['team']]} in the {person['area']}, and this role's focus on {t1}"
            f" builds directly on that.",
            f"I have chosen this role first because it would let me build on my current work. Day to"
            f" day I {TEAM_WORK[person['team']]}, and a large part of that is {t1}."],
        2: [f"I have ranked this role second. It sits close to my current work - I"
            f" {TEAM_WORK[person['team']]} - but it would give me more responsibility for {t1}.",
            f"This is my second choice. Much of my experience would transfer directly, especially"
            f" {t1}, although it would be a step away from my current focus."],
        3: [f"This is my third choice because it is further from my current role, but I have done"
            f" some {fam['work']} work before and would welcome the chance to develop it.",
            f"I have put this role third. I would need to grow in some areas, but I have supported"
            f" {t1} in the past and enjoyed it."],
    }
    middles = [
        f"It would also make the best use of the relationships I have built with {fam['people']},"
        f" which matters as much as the technical side of the job.",
        f"I have a particular interest in {rng.choice(INTERESTS)}, and this role would give me the"
        f" chance to apply that across the programme.",
        f"Being based in the {person['area']}, I already know many of the schemes and people this role"
        f" would work with.",
        f"I see it as a good opportunity to develop my skills in {t2} while still using what I know.",
    ]
    closers = ["I am confident I could contribute from day one.",
               "I would be keen to bring that experience to the new structure.", ""]
    parts = [rng.choice(openers[rank])] + rng.sample(middles, 2) + [rng.choice(closers)]
    return " ".join(p for p in parts if p)


def more_answer(rng, person):
    quals = rng.sample(QUALS, rng.choice([1, 1, 2]))
    years = rng.choice(["three", "four", "five", "six", "eight", "ten"])
    team = person["team"].lower()
    return (f"{' and '.join(quals)}. {years.capitalize()} years' experience in {team}. "
            f"{rng.choice(EXTRAS)}")


def build(seed, presenters):
    rng = random.Random(seed)
    roles = [dict(key=k, name=n, grade=g, family=f, serves=s, default=d)
             for k, n, g, f, s, d in ROLES]
    by_key = {r["key"]: r for r in roles}

    # -- people -------------------------------------------------------------
    grades = ["SG4"] * 9 + ["SG5"] * 17 + ["SG6"] * 10
    rng.shuffle(grades)
    staff = []
    for i, name in enumerate(STAFF_NAMES):
        staff.append(dict(name=name, emp=str(900101 + i), email=email_for(name),
                          grade=grades[i], area=REGIONS[i % len(REGIONS)],
                          team=TEAMS[(i + i // len(REGIONS)) % len(TEAMS)],
                          admin=False, presenter=False))
    pres = []
    for i, p in enumerate(presenters):
        pres.append(dict(name=p["Name"].strip(), emp=p["EmployeeID"].strip(),
                         email=p["Email"].strip().lower(),
                         grade=(p.get("Grade") or "SG5").strip(),
                         area=(p.get("Area") or "Midlands").strip(),
                         team=(p.get("Team") or "Programme Delivery").strip(),
                         admin=True, presenter=True))

    # -- eligibility --------------------------------------------------------
    def eligible(person):
        grp = REGION_GROUP.get(person["area"])
        same = [r for r in roles if r["grade"] == person["grade"]]
        mine = [r for r in same if r["serves"] is None or grp in r["serves"]]
        others = [r for r in same if r not in mine]
        rng.shuffle(others)
        picked = mine + others[: 1 if len(mine) >= 3 else 3 - len(mine) + 1]
        return sorted(picked, key=lambda r: r["key"])

    elig = {}
    for p in staff:
        elig[p["emp"]] = eligible(p)
    presenter_roles = ["R05", "R07", "R09", "R10", "R11"]
    presenter_aligned = ["R09", "R07", "R10", "R11", "R05"]
    for p in pres:
        elig[p["emp"]] = [by_key[k] for k in presenter_roles]

    # -- stage of each fictional person -------------------------------------
    order = staff[:]
    rng.shuffle(order)
    stage = {}
    for i, p in enumerate(order):
        stage[p["emp"]] = "not started" if i == 0 else ("in progress" if i <= 2 else "completed")

    # -- rankings -----------------------------------------------------------
    ranking = {}
    for p in staff:
        if stage[p["emp"]] == "not started":
            continue
        grp = REGION_GROUP.get(p["area"])

        def score(r):
            s = rng.random()
            if r["serves"] and grp in r["serves"]:
                s += 1.2
            if r["family"] in TEAM_FIT.get(p["team"], ()):
                s += 1.0
            return s
        ranking[p["emp"]] = sorted(elig[p["emp"]], key=score, reverse=True)

    # -- outcomes for the completed fictional staff --------------------------
    completed = [p for p in order if stage[p["emp"]] == "completed"]
    outcomes = (["rejected"] * len(REJECTIONS) + ["draft"] + ["accepted"] * 22)
    outcomes += ["awaiting"] * (len(completed) - len(outcomes))
    outcome = {p["emp"]: o for p, o in zip(completed, outcomes)}
    for p in staff:
        outcome.setdefault(p["emp"], "awaiting")

    def aligned_role(p):
        ranked = ranking.get(p["emp"])
        if not ranked:
            return elig[p["emp"]][0]
        o = outcome[p["emp"]]
        if o in ("rejected", "draft"):
            pool = ranked[3:] or ranked[2:3] or ranked[-1:]
            return rng.choice(pool)
        pick = rng.random()
        idx = 0 if pick < 0.65 else (1 if pick < 0.9 else 2)
        return ranked[min(idx, len(ranked) - 1)]

    # -- rows ---------------------------------------------------------------
    t = {name: [] for name in
         ("Roles", "People", "Eligibilities", "Preferences", "PreferenceResponses", "Alignments")}
    t["Roles"].append(["RoleName", "RoleKey", "ShortDescription", "Purpose", "Responsibilities",
                       "Requirements", "GradeContext", "Active", "DefaultOption"])
    for r in roles:
        f = FAMILY_TEXT[r["family"]]
        t["Roles"].append([r["name"], r["key"], f["short"], f["purpose"], "\n".join(f["resp"]),
                           "\n".join(f["req"]), GRADE_CONTEXT[r["grade"]], "Yes",
                           "Yes" if r["default"] else "No"])

    t["People"].append(["Name", "EmployeeID", "Email", "Grade", "Area", "Team", "IsAdmin"])
    for p in pres + staff:
        t["People"].append([p["name"], p["emp"], p["email"], p["grade"], p["area"], p["team"],
                            "Yes" if p["admin"] else "No"])

    t["Eligibilities"].append(["Name", "EmployeeID", "RoleKey", "Area", "Grade"])
    for p in pres + staff:
        for r in elig[p["emp"]]:
            t["Eligibilities"].append([p["name"], p["emp"], r["key"], p["area"], p["grade"]])

    t["Preferences"].append(["Name", "EmployeeID", "RoleKey", "Rank", "SubmittedBy",
                             "SubmittedOn", "Stage1Status"])
    t["PreferenceResponses"].append(["Name", "EmployeeID", "RoleKey", "QIndex", "QuestionText",
                                     "ResponseText", "SubmittedOn", "Stage2Status"])
    pref_no, resp_no = 5001, 7001
    stage1_start = dt.datetime(2026, 9, 7)
    for p in staff:
        ranked = ranking.get(p["emp"])
        if not ranked:
            continue
        when = working_time(rng, stage1_start, 12)
        for n, r in enumerate(ranked, start=1):
            t["Preferences"].append([str(pref_no), p["emp"], r["key"], n, p["email"], when,
                                     "Submitted"])
            pref_no += 1
        done = stage[p["emp"]] == "completed"
        answered = when + dt.timedelta(minutes=rng.randint(20, 240))
        for n, r in enumerate(ranked[:3], start=1):
            for q in (0, 1):
                text = why_answer(rng, p, r, n) if q == 0 else more_answer(rng, p)
                if not done:  # half-finished: only the first answer started
                    text = text if (n, q) == (1, 0) else ""
                t["PreferenceResponses"].append([
                    str(resp_no), p["emp"], r["key"], q,
                    (Q1_START + ORDINAL[n] + Q1_END) if q == 0 else Q2,
                    text, answered if done else None, "Submitted" if done else "Draft"])
                resp_no += 1

    t["Alignments"].append(["EmployeeID", "AssignedRoleName", "AssignedRoleKey", "AssignedReason",
                            "Decision", "RejectReasons", "RejectComments", "AlignmentStatus",
                            "DecisionOn", "DecisionBy", "LineManagerEmail"])
    decided_start = dt.datetime(2026, 10, 5)
    rejections = iter(REJECTIONS)
    first_presenter_reports = 0
    for p in staff:
        r = aligned_role(p)
        o = outcome[p["emp"]]
        row = [p["emp"], r["name"], r["key"], "", "", "", "", "", None, "", ""]
        if o in ("accepted", "rejected", "draft"):
            lm = rng.choice(LINE_MANAGERS)
            if pres and o == "accepted" and first_presenter_reports < 5:
                lm = pres[0]["email"]
                first_presenter_reports += 1
            row[10] = lm
        if o == "accepted":
            row[4], row[7] = "Accepted", "Submitted"
            row[8], row[9] = working_time(rng, decided_start, 11), p["email"]
        elif o == "rejected":
            reasons, comments = next(rejections)
            row[4], row[5], row[6], row[7] = "Rejected", reasons, comments, "Submitted"
            row[8], row[9] = working_time(rng, decided_start, 11), p["email"]
        elif o == "draft":
            row[5], row[6], row[7] = DRAFT_REJECTION[0], DRAFT_REJECTION[1], "Draft"
        t["Alignments"].append(row)
    for i, p in enumerate(pres):
        k = presenter_aligned[i % len(presenter_aligned)]
        t["Alignments"].append([p["emp"], by_key[k]["name"], k, "", "", "", "", "", None, "", ""])

    # -- sanity checks the import would otherwise find the hard way ---------
    for row in t["Roles"][1:]:
        for v in row[:7]:
            assert len(v) <= 100, f"Roles text over 100 characters: {v!r}"
    for row in t["PreferenceResponses"][1:]:
        assert len((row[5] or "").split()) <= 150, "answer over 150 words"
    for row in t["Alignments"][1:]:
        assert len(row[6].split()) <= 150, "rejection comment over 150 words"
    emps = [r[1] for r in t["People"][1:]]
    assert len(emps) == len(set(emps)), "duplicate EmployeeID in People"
    return t


def save(tables, out):
    os.makedirs(out, exist_ok=True)
    paths = []
    for name, rows in tables.items():
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.title = name
        for row in rows:
            ws.append([None if v == "" else v for v in row])
        for row in ws.iter_rows():
            for c in row:
                c.font = Font(name="Arial", bold=c.row == 1)
                if isinstance(c.value, dt.datetime):
                    c.number_format = "dd/mm/yyyy hh:mm"
                elif isinstance(c.value, str):
                    c.number_format = "@"
        for col in ws.columns:
            ws.column_dimensions[col[0].column_letter].width = min(
                60, max(10, max(len(str(c.value or "").split("\n")[0]) for c in col) + 2))
        path = os.path.join(out, f"RolePreference_{name}_DEMO.xlsx")
        wb.save(path)
        paths.append((path, len(rows) - 1))
    return paths


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="folder to write the six .xlsx files to")
    ap.add_argument("--presenters", help="CSV of presenters: Name,EmployeeID,Email[,Grade,Area,Team]")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    presenters = []
    if a.presenters:
        with open(a.presenters, newline="", encoding="utf-8-sig") as fh:
            presenters = [r for r in csv.DictReader(fh) if (r.get("Email") or "").strip()]
    for path, n in save(build(a.seed, presenters), a.out):
        print(f"{n:4d} rows  {path}")


if __name__ == "__main__":
    main()
