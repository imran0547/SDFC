"""Synthetic two-org Salesforce consolidation scenario with ground truth.

Produces two source "orgs" (A = acquirer, B = acquired) whose schemas,
picklists, date formats and phone formats differ, with known cross-org and
within-org duplicates, hard negatives (similar but distinct entities) and
injected defects. Ground truth is written separately and is never read by
the pipeline; it is used only by the evaluation code.
"""
from __future__ import annotations

import json
import os
import random
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

from faker import Faker

CENTRAL = ZoneInfo("America/Chicago")

INDUSTRY_CANON = ["Technology", "Finance", "Healthcare", "Manufacturing",
                  "Retail", "Energy", "Education", "Other"]
# Org B uses its own vocabulary; several values map many-to-one.
INDUSTRY_B = {
    "Technology": ["Tech", "Hi-Tech"],
    "Finance": ["Financial Services", "Banking"],
    "Healthcare": ["Health Care"],
    "Manufacturing": ["Mfg"],
    "Retail": ["Retail"],
    "Energy": ["Oil & Gas", "Utilities"],
    "Education": ["Education"],
    "Other": ["Misc"],
}
UNMAPPED_B_INDUSTRY = ["Agritech", "Space Systems"]          # not in mapping table
STAGE_CANON = ["Prospecting", "Qualification", "Proposal", "Negotiation",
               "Closed Won", "Closed Lost"]
STAGE_B = {"Prospecting": "Stage 1", "Qualification": "Stage 2",
           "Proposal": "Stage 3", "Negotiation": "Stage 4",
           "Closed Won": "Won", "Closed Lost": "Lost"}
UNMAPPED_B_STAGE = ["On Hold"]
NICKNAMES = {"Robert": "Bob", "William": "Bill", "Elizabeth": "Liz",
             "James": "Jim", "Michael": "Mike", "Jennifer": "Jen",
             "Christopher": "Chris", "Katherine": "Kate", "Richard": "Rick",
             "Thomas": "Tom", "Daniel": "Dan", "Matthew": "Matt",
             "Joseph": "Joe", "Anthony": "Tony", "Patricia": "Pat",
             "Margaret": "Maggie", "Steven": "Steve", "Andrew": "Andy",
             "Jessica": "Jess", "Nicholas": "Nick"}
SUFFIXES = ["Inc", "Inc.", "Incorporated", "LLC", "Ltd", "Corp", "Corporation",
            "Co", "Group", "PLC"]
SIBLING_WORDS = ["Holdings", "Logistics", "Labs", "Capital", "Services",
                 "Partners", "International", "Systems"]


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _b_datetime(dt: datetime) -> str:
    return dt.astimezone(CENTRAL).strftime("%m/%d/%Y %I:%M %p")


def _phone_fmt(digits: str, rng: random.Random) -> str:
    a, b, c = digits[:3], digits[3:6], digits[6:]
    return rng.choice([f"({a}) {b}-{c}", f"{a}.{b}.{c}", f"+1 {a} {b} {c}",
                       f"{a}-{b}-{c}", f"1{a}{b}{c}"])


def _typo(s: str, rng: random.Random) -> str:
    if len(s) < 4:
        return s
    i = rng.randrange(1, len(s) - 1)
    op = rng.random()
    if op < 0.33:                                    # transpose
        return s[:i] + s[i + 1] + s[i] + s[i + 2:]
    if op < 0.66:                                    # delete
        return s[:i] + s[i + 1:]
    ch = rng.choice("abcdefghijklmnopqrstuvwxyz")   # substitute
    return s[:i] + ch + s[i + 1:]


def _perturb_company(name: str, rng: random.Random) -> str:
    out = name
    r = rng.random()
    if r < 0.30:
        out = _typo(out, rng)
    elif r < 0.55:
        parts = out.split()
        if parts and parts[-1].strip(".") in [s.strip(".") for s in SUFFIXES]:
            parts[-1] = rng.choice(SUFFIXES)
        else:
            parts.append(rng.choice(SUFFIXES))
        out = " ".join(parts)
    elif r < 0.70:
        out = out.replace(" and ", " & ") if " and " in out else out.replace(" & ", " and ")
    elif r < 0.85:
        out = out.upper()
    if rng.random() < 0.15:
        out = _typo(out, rng)
    return out


def _perturb_person(first: str, last: str, rng: random.Random):
    r = rng.random()
    if r < 0.25 and first in NICKNAMES:
        first = NICKNAMES[first]
    elif r < 0.45:
        last = _typo(last, rng)
    elif r < 0.60:
        first = _typo(first, rng)
    elif r < 0.70:
        first, last = first.upper(), last.upper()
    elif r < 0.78:
        first = first[0] + "."
    return first, last


def generate(n_accounts: int, out_dir: str, seed: int = 7) -> dict:
    rng = random.Random(seed)
    fake = Faker("en_US")
    Faker.seed(seed)
    os.makedirs(out_dir, exist_ok=True)
    start = datetime(2019, 1, 1, tzinfo=timezone.utc)
    span_days = (datetime(2025, 12, 31, tzinfo=timezone.utc) - start).days

    def rand_dates():
        c = start + timedelta(days=rng.randrange(span_days), seconds=rng.randrange(86400))
        m = c + timedelta(days=rng.randrange(0, 400), seconds=rng.randrange(86400))
        return c, m

    # ---------------- canonical entity universe ----------------
    used_names = set()
    acc_entities = []
    while len(acc_entities) < n_accounts:
        base = fake.company()
        if base in used_names:
            continue
        used_names.add(base)
        dom = "".join(ch for ch in base.lower() if ch.isalnum())[:20] + rng.choice([".com", ".io", ".net", ".co"])
        e = dict(eid=f"ACC{len(acc_entities):07d}", name=base, city=fake.city(),
                 state=fake.state_abbr(), phone=fake.numerify("2#########"),
                 domain=dom, industry=rng.choice(INDUSTRY_CANON),
                 revenue=rng.randrange(1, 5000) * 10000)
        acc_entities.append(e)
        if rng.random() < 0.03 and len(acc_entities) < n_accounts:   # hard negative sibling
            core = base.split(",")[0].split(" and ")[0].split()[0]
            sib = f"{core} {rng.choice(SIBLING_WORDS)}"
            if sib not in used_names:
                used_names.add(sib)
                # subsidiaries often share the parent's web domain (trap for domain-only rules)
                sdom = dom if rng.random() < 0.5 else "".join(ch for ch in sib.lower() if ch.isalnum())[:20] + ".com"
                acc_entities.append(dict(eid=f"ACC{len(acc_entities):07d}", name=sib,
                                         city=fake.city(), state=fake.state_abbr(),
                                         phone=fake.numerify("2#########"), domain=sdom,
                                         industry=rng.choice(INDUSTRY_CANON),
                                         revenue=rng.randrange(1, 5000) * 10000))

    src = {"A": {"Account": [], "Contact": [], "Opportunity": []},
           "B": {"Account": [], "Contact": [], "Opportunity": []}}
    truth = {}                                   # source id -> {entity, defects, object, org}
    counters = {"A": 0, "B": 0}

    def new_id(org, prefix):
        counters[org] += 1
        return f"{prefix}{org}{counters[org]:011d}"

    def maybe_defects(obj, org):
        d = []
        if obj == "Contact":
            if rng.random() < 0.010: d.append("invalid_email")
            if rng.random() < 0.005: d.append("missing_required")
            if rng.random() < 0.005: d.append("orphan_reference")
        if obj == "Opportunity":
            if rng.random() < 0.005: d.append("negative_amount")
            if rng.random() < 0.005: d.append("orphan_reference")
            if org == "B" and rng.random() < 0.005: d.append("unmapped_picklist")
        if obj == "Account":
            if org == "B" and rng.random() < 0.005: d.append("unmapped_picklist")
            if rng.random() < 0.003: d.append("missing_required")
            if rng.random() < 0.003: d.append("revenue_unit_error")   # plausible-looking, rule-free
        if obj == "Contact" and rng.random() < 0.005: d.append("swapped_names")  # semantic error
        if org == "B" and rng.random() < 0.003: d.append("unparseable_date")
        return d

    def account_record(e, org, perturb):
        name = _perturb_company(e["name"], rng) if perturb else e["name"]
        dom = e["domain"]
        if perturb and rng.random() < 0.25:
            dom = None
        elif dom and rng.random() < 0.3:
            dom = rng.choice(["www.", "https://", "http://www."]) + dom
        phone = _phone_fmt(e["phone"], rng) if not (perturb and rng.random() < 0.15) else None
        if perturb and phone and rng.random() < 0.20:          # local office line instead of HQ
            phone = _phone_fmt(fake.numerify("2#########"), rng)
        city = fake.city() if (perturb and rng.random() < 0.20) else e["city"]   # billing vs HQ address
        revenue = e["revenue"]
        c, m = rand_dates()
        defects = maybe_defects("Account", org)
        if "revenue_unit_error" in defects:
            revenue = revenue * 1000
        sid = new_id(org, "001")
        if "missing_required" in defects:
            name = None
        if org == "A":
            rec = dict(Id=sid, Name=name, BillingCity=city, BillingState=e["state"],
                       Phone=phone, Website=dom, Industry=e["industry"],
                       AnnualRevenue=revenue, CreatedDate=_iso(c), LastModifiedDate=_iso(m))
        else:
            ind = rng.choice(UNMAPPED_B_INDUSTRY) if "unmapped_picklist" in defects else rng.choice(INDUSTRY_B[e["industry"]])
            cd = "13/45/2021 99:00 XM" if "unparseable_date" in defects else _b_datetime(c)
            rec = {"Id": sid, "Company_Name__c": name, "City__c": city, "State__c": e["state"],
                   "Phone_Number__c": phone, "Web__c": dom, "Sector__c": ind,
                   "Revenue_USD__c": revenue, "Created__c": cd, "Modified__c": _b_datetime(m)}
        truth[sid] = dict(entity=e["eid"], defects=defects, object="Account", org=org)
        src[org]["Account"].append(rec)
        return sid

    def contact_record(ce, org, acc_sid, perturb, all_acc_ids):
        first, last = ce["first"], ce["last"]
        email = ce["email"]
        if perturb:
            first, last = _perturb_person(first, last, rng)
            r = rng.random()
            if r < 0.25: email = email.upper()
            elif r < 0.45: email = f"{ce['first'].lower()}{rng.randrange(10,99)}@{rng.choice(['gmail.com','outlook.com','yahoo.com'])}"
            elif r < 0.55: email = None
        phone = _phone_fmt(ce["phone"], rng) if not (perturb and rng.random() < 0.3) else None
        c, m = rand_dates()
        defects = maybe_defects("Contact", org)
        sid = new_id(org, "003")
        if "invalid_email" in defects:
            base = (ce["email"] or "x@y.com")
            email = rng.choice([base.replace("@", "@@"), base.replace("@", ""), base.split("@")[0] + "@"])
        if "missing_required" in defects:
            last = None
        if "swapped_names" in defects:
            first, last = last, first
        if "orphan_reference" in defects:
            acc_sid = f"001{org}MISSING{rng.randrange(10**6):06d}"
        if org == "A":
            rec = dict(Id=sid, FirstName=first, LastName=last, Email=email, Phone=phone,
                       Title=ce["title"], AccountId=acc_sid, CreatedDate=_iso(c), LastModifiedDate=_iso(m))
        else:
            cd = "13/45/2021 99:00 XM" if "unparseable_date" in defects else _b_datetime(c)
            rec = {"Id": sid, "First__c": first, "Last__c": last, "Email__c": email,
                   "Mobile__c": phone, "Job_Title__c": ce["title"], "Company__c": acc_sid,
                   "Created__c": cd, "Modified__c": _b_datetime(m)}
        truth[sid] = dict(entity=ce["eid"], defects=defects, object="Contact", org=org)
        src[org]["Contact"].append(rec)

    def opp_record(org, acc_sid, n):
        c, m = rand_dates()
        defects = maybe_defects("Opportunity", org)
        sid = new_id(org, "006")
        amount = rng.randrange(5, 2000) * 500
        if "negative_amount" in defects:
            amount = -amount
        if "orphan_reference" in defects:
            acc_sid = f"001{org}MISSING{rng.randrange(10**6):06d}"
        stage = rng.choice(STAGE_CANON)
        close = (c + timedelta(days=rng.randrange(10, 300))).date()
        if org == "A":
            rec = dict(Id=sid, Name=f"Deal {n}", Amount=amount, StageName=stage,
                       CloseDate=close.isoformat(), AccountId=acc_sid,
                       CreatedDate=_iso(c), LastModifiedDate=_iso(m))
        else:
            ph = rng.choice(UNMAPPED_B_STAGE) if "unmapped_picklist" in defects else STAGE_B[stage]
            cd = "13/45/2021 99:00 XM" if "unparseable_date" in defects else _b_datetime(c)
            rec = {"Id": sid, "Deal_Name__c": f"Deal {n}", "Value__c": amount, "Phase__c": ph,
                   "Expected_Close__c": close.strftime("%m/%d/%Y"), "Customer__c": acc_sid,
                   "Created__c": cd, "Modified__c": _b_datetime(m)}
        truth[sid] = dict(entity=None, defects=defects, object="Opportunity", org=org)
        src[org]["Opportunity"].append(rec)

    contact_n = 0
    opp_n = 0
    for e in acc_entities:
        r = rng.random()
        orgs = ["A"] if r < 0.50 else (["B"] if r < 0.85 else ["A", "B"])
        acc_sids = {}
        for org in orgs:
            perturb = (org == "B" and "A" in orgs)          # cross-org copy is the noisy one
            acc_sids[org] = [account_record(e, org, perturb)]
            if rng.random() < 0.04:                          # within-org duplicate
                acc_sids[org].append(account_record(e, org, True))
        # contacts
        k = max(1, min(8, int(rng.gauss(3, 1.5))))
        people = []
        for _ in range(k):
            f, l = fake.first_name(), fake.last_name()
            people.append((f, l))
            if rng.random() < 0.02:                          # hard negative: same surname, same account
                people.append((fake.first_name(), l))
        for f, l in people:
            local = f"{f.lower()}.{l.lower()}"
            ce = dict(eid=f"CON{contact_n:07d}", first=f, last=l,
                      email=f"{local}@{e['domain']}", phone=fake.numerify("3#########"),
                      title=fake.job()[:60])
            contact_n += 1
            if len(orgs) == 2:
                rr = rng.random()
                corgs = ["A"] if rr < 0.4 else (["B"] if rr < 0.7 else ["A", "B"])
            else:
                corgs = orgs
            for org in corgs:
                perturb = (org == "B" and "A" in corgs)
                contact_record(ce, org, rng.choice(acc_sids[org]), perturb, None)
                if rng.random() < 0.03:
                    contact_record(ce, org, rng.choice(acc_sids[org]), True, None)
        # opportunities (transactions: not deduplicated, only re-parented)
        for org in orgs:
            for _ in range(max(0, int(rng.gauss(2.5, 1.2)))):
                opp_record(org, rng.choice(acc_sids[org]), opp_n)
                opp_n += 1

    for org in ("A", "B"):
        for obj, rows in src[org].items():
            with open(os.path.join(out_dir, f"org{org}_{obj}.jsonl"), "w") as fh:
                for row in rows:
                    fh.write(json.dumps(row) + "\n")
    with open(os.path.join(out_dir, "truth.json"), "w") as fh:
        json.dump(truth, fh)
    summary = {f"{org}.{obj}": len(rows) for org in src for obj, rows in src[org].items()}
    summary["entities.Account"] = len(acc_entities)
    summary["entities.Contact"] = contact_n
    summary["total_source_records"] = sum(len(r) for o in src.values() for r in o.values())
    with open(os.path.join(out_dir, "summary.json"), "w") as fh:
        json.dump(summary, fh, indent=2)
    return summary


if __name__ == "__main__":
    import sys
    print(generate(int(sys.argv[1]), sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 7))
