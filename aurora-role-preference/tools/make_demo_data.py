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

DEMO MODE. powerfx_demo_block() writes a smaller set of the same kind of data
as Power Fx that builds in-memory collections, with whoever is signed in added
as the presenter at run time - so it holds no real person at all.
tools/gen_paste.py puts it at the top of paste/demo-app/App_OnStart.demo.powerfx
for a copy of the app that reads no Dataverse table (docs/demo-mode.md).
"""

import argparse
import csv
import datetime as dt
import os
import random
import re
import sys



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


def why_answer(rng, person, role, rank, middles_n=2):
    fam = FAMILY_TEXT[role["family"]]
    t1, t2 = rng.sample(fam["tasks"], 2)
    openers = {
        1: [f"This is my first choice because it is closest to what I already do. I currently"
            f" {TEAM_WORK[person['team']]} in the {person['area']}, and this role's focus on {t1}"
            f" builds directly on that.",
            f"I have chosen this role first because it would let me build on my current work. Day to"
            f" day I {TEAM_WORK[person['team']]}, and this role's focus on {t1} is a natural next step."],
        2: [f"I have ranked this role second. It sits close to my current work - I"
            f" {TEAM_WORK[person['team']]} - but it would give me more responsibility for {t1}.",
            f"This is my second choice. Much of my experience would transfer, and I would like more"
            f" involvement in {t1}, although it would be a step away from my current focus."],
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
    parts = [rng.choice(openers[rank])] + rng.sample(middles, middles_n) + [rng.choice(closers)]
    return " ".join(p for p in parts if p)


def more_answer(rng, person):
    quals = rng.sample(QUALS, rng.choice([1, 1, 2]))
    years = rng.choice(["three", "four", "five", "six", "eight", "ten"])
    team = person["team"].lower()
    return (f"{' and '.join(quals)}. {years.capitalize()} years' experience in {team}. "
            f"{rng.choice(EXTRAS)}")


def build(seed, presenters, staff_count=len(STAFF_NAMES), mix=(len(REJECTIONS), 1, 22),
          middles_n=2, lm_placeholder=None):
    """mix = (rejected, draft rejection, accepted) among people who finished the
    form; the rest of them are awaiting a response. lm_placeholder stands in for
    the first presenter's address as line manager when no presenters are given
    (the in-app demo swaps in whoever is signed in)."""
    rng = random.Random(seed)
    roles = [dict(key=k, name=n, grade=g, family=f, serves=s, default=d)
             for k, n, g, f, s, d in ROLES]
    by_key = {r["key"]: r for r in roles}

    # -- people -------------------------------------------------------------
    n4, n6 = round(staff_count * 9 / 36), round(staff_count * 10 / 36)
    grades = ["SG4"] * n4 + ["SG5"] * (staff_count - n4 - n6) + ["SG6"] * n6
    rng.shuffle(grades)
    staff = []
    for i, name in enumerate(STAFF_NAMES[:staff_count]):
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
    n_rej, n_draft, n_acc = mix
    outcomes = (["rejected"] * n_rej + ["draft"] * n_draft + ["accepted"] * n_acc)[:len(completed)]
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
                text = why_answer(rng, p, r, n, middles_n) if q == 0 else more_answer(rng, p)
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
            target = pres[0]["email"] if pres else lm_placeholder
            if target and o == "accepted" and first_presenter_reports < 5:
                lm = target
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


# ---------------------------------------------------------------------------
# In-app demo data: the same kind of fictional data, written as Power Fx that
# loads collections, for the DEMO MODE copy of the app (docs/demo-mode.md).
# tools/gen_paste.py puts this at the top of paste/demo-app/App_OnStart.demo.powerfx.
# Smaller than the spreadsheet set (20 staff, shorter answers) so the OnStart
# stays a comfortable size to paste.
# ---------------------------------------------------------------------------

DEMO_PRESENTER_ID = "100001"
DEMO_PRESENTER_ROLES = "R05,R07,R09,R10,R11"
DEMO_PRESENTER_ALIGNED = "R09"


def _fx(v):
    """A Python value as a Power Fx literal."""
    if v is None:
        return "Blank()"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, dt.datetime):
        return f"DateTime({v.year}, {v.month}, {v.day}, {v.hour}, {v.minute}, 0)"
    if isinstance(v, (int, float)):
        return str(v)
    parts = [p.replace('"', '""') for p in str(v).split("\n")]
    return " & Char(10) & ".join(f'"{p}"' for p in parts)


def _record(fields, indent):
    pad = " " * indent
    return pad + "{" + ", ".join(f"{k}: {_fx(v)}" for k, v in fields) + "}"


def powerfx_demo_block(seed=7):
    t = build(seed, [], staff_count=20, mix=(3, 1, 10), middles_n=1, lm_placeholder="presenter")
    rows = {name: [dict(zip(r[0], x)) for x in r[1:]] for name, r in ((n, t[n]) for n in t)}
    by_emp = lambda table: {e: [x for x in rows[table] if x["EmployeeID"] == e]
                            for e in {x["EmployeeID"] for x in rows[table]}}
    elig, prefs, resp = by_emp("Eligibilities"), by_emp("Preferences"), by_emp("PreferenceResponses")

    staff = []
    for p in rows["People"]:
        e = p["EmployeeID"]
        ranked = sorted(prefs.get(e, []), key=lambda x: x["Rank"])
        answers = resp.get(e, [])
        done = any(a["Stage2Status"] == "Submitted" for a in answers)
        stage = "done" if done else ("part" if ranked else "none")
        rec = [("EmpId", e), ("Name", p["Name"]), ("Email", p["Email"]), ("Grade", p["Grade"]),
               ("Area", p["Area"]), ("Team", p["Team"]),
               ("Roles", ",".join(x["RoleKey"] for x in elig[e])),
               ("Ranked", ",".join(x["RoleKey"] for x in ranked)), ("Stage", stage),
               ("RankedOn", ranked[0]["SubmittedOn"] if ranked else None),
               ("AnsweredOn", next((a["SubmittedOn"] for a in answers if a["SubmittedOn"]), None))]
        keys = [x["RoleKey"] for x in ranked[:3]]
        for n in (1, 2, 3):
            for q, letter in ((0, "a"), (1, "b")):
                hit = [a for a in answers if keys[n - 1:n] == [a["RoleKey"]] and a["QIndex"] == q]
                rec.append((f"A{n}{letter}", (hit[0]["ResponseText"] or "") if hit else ""))
        staff.append((stage, rec))
    staff.sort(key=lambda x: ["done", "part", "none"].index(x[0]))  # typed values first

    align = sorted(rows["Alignments"], key=lambda a: a["DecisionOn"] is None)
    out = []
    w = out.append
    w("/* =============================================================================")
    w("   DEMO DATA - fictional, held in memory only (GENERATED by tools/gen_paste.py")
    w("   from tools/make_demo_data.py - edit those, not this block).")
    w("   Every table the live app uses is replaced in this copy by one of these")
    w("   collections, and the copy has no Dataverse tables at all, so nothing here")
    w("   is read from or written to the real data. Refreshing the browser (or Run")
    w("   OnStart in Studio) starts the demo again from scratch.")
    w("   Staff use example.com addresses - a domain reserved for examples, so no")
    w("   email can reach anyone. Whoever is signed in joins as the presenter.")
    w("   ============================================================================ */")
    w("/* true = you see the admin pages. false = you see them as a line manager:")
    w("   only the five fictional staff who named you as their line manager. */")
    w("Set(varDemoPresenterIsAdmin, true);")
    w(f"Set(varDemoQ1a, {_fx(Q1_START)});")
    w(f"Set(varDemoQ1b, {_fx(Q1_END)});")
    w(f"Set(varDemoQ2, {_fx(Q2)});")
    w("ClearCollect(")
    w("    colDemoRoles,")
    roles = rows["Roles"]
    for i, r in enumerate(roles):
        fields = [(k, r[k]) for k in ("RoleKey", "RoleName", "ShortDescription", "Purpose",
                                      "Responsibilities", "Requirements", "GradeContext")]
        fields += [("Active", r["Active"] == "Yes"), ("DefaultOption", r["DefaultOption"] == "Yes")]
        w(_record(fields, 4) + ("," if i < len(roles) - 1 else ""))
    w(");")
    w("ClearCollect(")
    w("    colDemoStaff,")
    for i, (_, rec) in enumerate(staff):
        meta, answers = rec[:11], rec[11:]
        w("    {")
        w("        " + ", ".join(f"{k}: {_fx(v)}" for k, v in meta[:6]) + ",")
        w("        " + ", ".join(f"{k}: {_fx(v)}" for k, v in meta[6:]) + ",")
        for j, (k, v) in enumerate(answers):
            w(f"        {k}: {_fx(v)}" + ("," if j < len(answers) - 1 else ""))
        w("    }" + ("," if i < len(staff) - 1 else ""))
    w(");")
    w("ClearCollect(")
    w("    colDemoAlignments,")
    for i, a in enumerate(align):
        fields = [(k, a[k] if a[k] is not None or k == "DecisionOn" else "")
                  for k in ("EmployeeID", "AssignedRoleName", "AssignedRoleKey", "AssignedReason",
                            "Decision", "RejectReasons", "RejectComments", "AlignmentStatus",
                            "DecisionOn", "DecisionBy", "LineManagerEmail")]
        w(_record(fields, 4) + ("," if i < len(align) - 1 else ""))
    w(");")
    w("/* The tables the app reads, built from colDemoStaff. */")
    w("ClearCollect(colDemoPeople, ForAll(colDemoStaff As s, {Name: s.Name, EmployeeID: s.EmpId, Email: s.Email, Grade: s.Grade, Area: s.Area, Team: s.Team, IsAdmin: false}));")
    w("Clear(colDemoEligibilities);")
    w("ForAll(colDemoStaff As s, Collect(colDemoEligibilities, ForAll(Split(s.Roles, \",\") As k, {EmployeeID: s.EmpId, RoleKey: k.Value, Area: s.Area, Grade: s.Grade})));")
    w("Clear(colDemoPreferences);")
    w("ForAll(")
    w("    Filter(colDemoStaff, Stage <> \"none\") As s,")
    w("    Collect(")
    w("        colDemoPreferences,")
    w("        ForAll(")
    w("            Sequence(CountRows(Split(s.Ranked, \",\"))) As n,")
    w("            {EmployeeID: s.EmpId, RoleKey: Index(Split(s.Ranked, \",\"), n.Value).Value, Rank: n.Value, SubmittedBy: s.Email, SubmittedOn: s.RankedOn, Stage1Status: \"Submitted\"}")
    w("        )")
    w("    )")
    w(");")
    w("Clear(colDemoResponses);")
    w("ForAll(")
    w("    Filter(colDemoStaff, Stage <> \"none\") As s,")
    w("    With(")
    w("        {keys: Split(s.Ranked, \",\"), stat: If(s.Stage = \"done\", \"Submitted\", \"Draft\"), sOn: If(s.Stage = \"done\", s.AnsweredOn)},")
    w("        Collect(")
    w("            colDemoResponses,")
    specs = [(1, 0, "first", "A1a"), (1, 1, None, "A1b"), (2, 0, "second", "A2a"),
             (2, 1, None, "A2b"), (3, 0, "third", "A3a"), (3, 1, None, "A3b")]
    for i, (n, q, word, field) in enumerate(specs):
        qt = f'varDemoQ1a & "{word}" & varDemoQ1b' if word else "varDemoQ2"
        w(f"            {{EmployeeID: s.EmpId, RoleKey: Index(keys, {n}).Value, QIndex: {q}, QuestionText: {qt}, "
          f"ResponseText: s.{field}, SubmittedOn: sOn, Stage2Status: stat}}" + ("," if i < 5 else ""))
    w("        )")
    w("    )")
    w(");")
    w("/* The presenter: whoever is signed in, with five roles to rank, the form not")
    w("   yet filled in, and an aligned role waiting for a response. */")
    w(f'Collect(colDemoPeople, {{Name: User().FullName, EmployeeID: "{DEMO_PRESENTER_ID}", Email: Lower(User().Email), Grade: "SG5", Area: "Midlands", Team: "Programme Delivery", IsAdmin: varDemoPresenterIsAdmin}});')
    w(f'Collect(colDemoEligibilities, ForAll(Split("{DEMO_PRESENTER_ROLES}", ",") As k, {{EmployeeID: "{DEMO_PRESENTER_ID}", RoleKey: k.Value, Area: "Midlands", Grade: "SG5"}}));')
    w(f'Collect(colDemoAlignments, {{EmployeeID: "{DEMO_PRESENTER_ID}", AssignedRoleName: LookUp(colDemoRoles, RoleKey = "{DEMO_PRESENTER_ALIGNED}").RoleName, AssignedRoleKey: "{DEMO_PRESENTER_ALIGNED}", AssignedReason: "", Decision: "", RejectReasons: "", RejectComments: "", AlignmentStatus: "", DecisionOn: Blank(), DecisionBy: "", LineManagerEmail: ""}});')
    w('UpdateIf(colDemoAlignments, LineManagerEmail = "presenter", {LineManagerEmail: Lower(User().Email)});')
    w("")
    return "\n".join(out)


def save(tables, out):
    try:
        import openpyxl
        from openpyxl.styles import Font
    except ImportError:  # pragma: no cover
        sys.exit("openpyxl is required: pip install openpyxl")
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
