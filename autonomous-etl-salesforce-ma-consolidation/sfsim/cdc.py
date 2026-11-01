"""Change data capture: event generation, idempotent incremental apply with
incremental matching, data-health anomaly detection with a circuit breaker,
and an incremental-vs-full-rebuild equivalence check."""
from __future__ import annotations

import copy
import json
import os
import random
import statistics
import time
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from .generate import CENTRAL, _perturb_person, _phone_fmt
from .pipeline import (ACC_FIELDS, CON_FIELDS, MATCH_CONFIG, SOURCE_PRIORITY, _eq,
                       _first_sim, _weighted, transform_record)
from rapidfuzz.distance import JaroWinkler

T0 = datetime(2026, 1, 5, tzinfo=timezone.utc)
FIELD = {  # canonical -> raw field name per org
    "A": {"Account": {"Phone": "Phone", "Industry": "Industry", "Mod": "LastModifiedDate"},
          "Contact": {"Phone": "Phone", "Title": "Title", "Email": "Email", "Mod": "LastModifiedDate",
                      "AccountId": "AccountId"},
          "Opportunity": {"Amount": "Amount", "Stage": "StageName", "Mod": "LastModifiedDate"}},
    "B": {"Account": {"Phone": "Phone_Number__c", "Industry": "Sector__c", "Mod": "Modified__c"},
          "Contact": {"Phone": "Mobile__c", "Title": "Job_Title__c", "Email": "Email__c",
                      "Mod": "Modified__c", "AccountId": "Company__c"},
          "Opportunity": {"Amount": "Value__c", "Stage": "Phase__c", "Mod": "Modified__c"}},
}


def _ts(org, dt):
    if org == "A":
        return dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    return dt.astimezone(CENTRAL).strftime("%m/%d/%Y %I:%M %p")


def load_sources(data_dir):
    src = {}
    for org in ("A", "B"):
        for obj in ("Account", "Contact", "Opportunity"):
            with open(os.path.join(data_dir, f"org{org}_{obj}.jsonl")) as fh:
                src[(org, obj)] = {r["Id"]: r for r in map(json.loads, fh)}
    return src


def generate_events(src, truth, days=5, change_rate=0.02, dup_rate=0.01, seed=11,
                    anomaly=(3, 10)):
    """~change_rate of all records change per day, spread over hourly micro-batches."""
    rng = random.Random(seed)
    src = copy.deepcopy(src)
    total = sum(len(v) for v in src.values())
    per_day = int(total * change_rate)
    batches = []
    eid = 0
    new_n = 0
    stages_a = ["Prospecting", "Qualification", "Proposal", "Negotiation", "Closed Won", "Closed Lost"]
    stages_b = ["Stage 1", "Stage 2", "Stage 3", "Stage 4", "Won", "Lost"]
    keys = {k: list(v.keys()) for k, v in src.items()}
    for d in range(days):
        for h in range(24):
            evs = []
            n = per_day // 24
            is_anom = (d, h) == anomaly
            for _ in range(n):
                t = T0 + timedelta(days=d, hours=h, seconds=rng.randrange(3600))
                org = rng.choice("AB")
                r = rng.random()
                if r < 0.30 or is_anom:
                    obj = "Contact"
                elif r < 0.75:
                    obj = "Opportunity"
                else:
                    obj = "Account"
                f = FIELD[org][obj]
                kind = rng.random()
                if is_anom:
                    # upstream defect: a buggy sync job blanks e-mail and phone on contacts
                    rid = rng.choice(keys[(org, obj)])
                    rec = dict(src[(org, obj)][rid]); rec[f["Email"]] = None; rec[f["Phone"]] = None
                    rec[f["Mod"]] = _ts(org, t)
                    evs.append(dict(op="update", org=org, object=obj, record=rec))
                    continue
                if obj == "Opportunity" and kind < 0.10:
                    rid = rng.choice(keys[(org, obj)])
                    evs.append(dict(op="delete", org=org, object=obj, record={"Id": rid}))
                    continue
                if obj in ("Contact", "Opportunity") and kind < 0.30:
                    # create: new contact (sometimes a duplicate of an existing person in the
                    # other org) or new opportunity
                    new_n += 1
                    if obj == "Contact":
                        other = "B" if org == "A" else "A"
                        if rng.random() < 0.4:
                            base = src[(other, "Contact")][rng.choice(keys[(other, "Contact")])]
                            ent = truth[base["Id"]]["entity"]
                            fo = FIELD[other]["Contact"]
                            first = base.get("FirstName") or base.get("First__c") or "Pat"
                            last = base.get("LastName") or base.get("Last__c") or "Doe"
                            first, last = _perturb_person(first, last, rng)
                            email = base.get(fo["Email"])
                            phone = base.get(fo["Phone"])
                        else:
                            ent = f"CONNEW{new_n:07d}"
                            first, last = rng.choice(["Ana", "Luis", "Mei", "Omar", "Sara"]), f"New{new_n}"
                            email, phone = f"{first.lower()}.{last.lower()}@example.org", _phone_fmt(f"5{rng.randrange(10**9):09d}", rng)
                        acc = rng.choice(keys[(org, "Account")])
                        rid = f"003{org}N{new_n:010d}"
                        if org == "A":
                            rec = dict(Id=rid, FirstName=first, LastName=last, Email=email, Phone=phone,
                                       Title="Analyst", AccountId=acc, CreatedDate=_ts(org, t),
                                       LastModifiedDate=_ts(org, t))
                        else:
                            rec = {"Id": rid, "First__c": first, "Last__c": last, "Email__c": email,
                                   "Mobile__c": phone, "Job_Title__c": "Analyst", "Company__c": acc,
                                   "Created__c": _ts(org, t), "Modified__c": _ts(org, t)}
                        truth[rid] = dict(entity=ent, defects=[], object="Contact", org=org)
                    else:
                        acc = rng.choice(keys[(org, "Account")])
                        rid = f"006{org}N{new_n:010d}"
                        amt = rng.randrange(5, 2000) * 500
                        if org == "A":
                            rec = dict(Id=rid, Name=f"New deal {new_n}", Amount=amt, StageName="Prospecting",
                                       CloseDate=(t + timedelta(days=60)).date().isoformat(), AccountId=acc,
                                       CreatedDate=_ts(org, t), LastModifiedDate=_ts(org, t))
                        else:
                            rec = {"Id": rid, "Deal_Name__c": f"New deal {new_n}", "Value__c": amt,
                                   "Phase__c": "Stage 1",
                                   "Expected_Close__c": (t + timedelta(days=60)).strftime("%m/%d/%Y"),
                                   "Customer__c": acc, "Created__c": _ts(org, t), "Modified__c": _ts(org, t)}
                        truth[rid] = dict(entity=None, defects=[], object="Opportunity", org=org)
                    evs.append(dict(op="create", org=org, object=obj, record=rec))
                    continue
                rid = rng.choice(keys[(org, obj)])
                rec = dict(src[(org, obj)][rid])
                if obj == "Account":
                    rec[f["Phone"]] = _phone_fmt(f"2{rng.randrange(10**9):09d}", rng)
                elif obj == "Contact":
                    if rng.random() < 0.5:
                        rec[f["Title"]] = rng.choice(["Director", "VP Sales", "Engineer", "Buyer"])
                    else:
                        rec[f["Phone"]] = _phone_fmt(f"3{rng.randrange(10**9):09d}", rng)
                else:
                    if rng.random() < 0.5:
                        rec[f["Amount"]] = abs(rec[f["Amount"]] or 0) + rng.randrange(1, 50) * 500
                    else:
                        rec[f["Stage"]] = rng.choice(stages_a if org == "A" else stages_b)
                rec[f["Mod"]] = _ts(org, t)
                evs.append(dict(op="update", org=org, object=obj, record=rec))
            for e in evs:
                eid += 1
                e["event_id"] = eid
                if e["op"] == "create":
                    src[(e["org"], e["object"])][e["record"]["Id"]] = e["record"]
                    keys[(e["org"], e["object"])].append(e["record"]["Id"])
                elif e["op"] == "update" and not is_anom:
                    src[(e["org"], e["object"])][e["record"]["Id"]] = e["record"]
            # at-least-once delivery: replay a few events from this or earlier batches
            replays = []
            pool = [x for b in batches[-3:] for x in b["events"]] + evs
            for _ in range(int(len(evs) * dup_rate)):
                replays.append(copy.deepcopy(rng.choice(pool)))
            batches.append(dict(day=d, hour=h, anomalous=is_anom, events=evs + replays))
    return batches


class IncrementalSync:
    def __init__(self, batch_result):
        m = batch_result["mdm"]
        self.con = batch_result["con"]
        self.members = {}
        for o in ("Account", "Contact"):
            for r in batch_result["accepted"][o]:
                self.members[r["src_id"]] = r
        self.acc_x = dict(m["acc_x"])
        self.con_x = dict(m["con_x"])
        self.clusters = defaultdict(set)
        for s, g in list(self.acc_x.items()) + list(self.con_x.items()):
            self.clusters[g].add(s)
        self.con_by_acc = defaultdict(set)
        for gid, g in m["con_golden"].items():
            self.con_by_acc[g["AccountGid"]].add(gid)
        self.email_idx = {}
        for s, g in self.con_x.items():
            e = self.members[s].get("k_email")
            if e:
                self.email_idx.setdefault(e, g)
        self.seen = set()
        self.next_con = len(m["con_golden"])
        self.opps = {r["src_id"]: r for r in batch_result["accepted"]["Opportunity"]}
        self.audit = []
        self.applied_event_ids = set()
        self.profile = []          # per-batch contact email null rate
        self.held = []

    def _golden(self, gid, fields):
        ms = [self.members[s] for s in self.clusters[gid]]
        ordered = sorted(ms, key=lambda r: (r.get("LastModifiedDate") or "",
                                            -SOURCE_PRIORITY[r["org"]]), reverse=True)
        return {f: next((m[f] for m in ordered if m.get(f) not in (None, "")), None) for f in fields}

    def _upsert_account(self, gid):
        g = self._golden(gid, ACC_FIELDS)
        self.con.execute("""UPDATE account SET name=?,city=?,state=?,phone=?,website=?,industry=?,
            annual_revenue=?,last_modified=? WHERE gid=?""",
                         (g["Name"], g["City"], g["State"], g["Phone"], g["Website"], g["Industry"],
                          g["AnnualRevenue"], g["LastModifiedDate"], gid))

    def _upsert_contact(self, gid, acc_gid):
        g = self._golden(gid, CON_FIELDS)
        created = min(self.members[s]["CreatedDate"] for s in self.clusters[gid]
                      if self.members[s].get("CreatedDate"))
        self.con.execute("""INSERT INTO contact VALUES (?,?,?,?,?,?,?,?,?)
            ON CONFLICT(gid) DO UPDATE SET first_name=excluded.first_name,
            last_name=excluded.last_name, email=excluded.email, phone=excluded.phone,
            title=excluded.title, last_modified=excluded.last_modified""",
                         (gid, acc_gid, g["FirstName"], g["LastName"], g["Email"], g["Phone"],
                          g["Title"], created, g["LastModifiedDate"]))

    def _match_contact(self, r, acc_gid):
        if r.get("k_email") and r["k_email"] in self.email_idx:
            return self.email_idx[r["k_email"]]
        w = MATCH_CONFIG["Contact"]["weights"]
        best, best_s = None, 0.0
        for gid in self.con_by_acc.get(acc_gid, ()):
            for s in self.clusters[gid]:
                c = self.members[s]
                ls = JaroWinkler.normalized_similarity(r["k_last"], c["k_last"]) \
                    if r["k_last"] and c["k_last"] else None
                sc = _weighted({"first": _first_sim(r["k_first"], c["k_first"]), "last": ls,
                                "email": _eq(r["k_email"], c["k_email"]),
                                "phone": _eq(r["k_phone"], c["k_phone"])}, w)
                if sc > best_s:
                    best, best_s = gid, sc
        return best if best_s >= MATCH_CONFIG["Contact"]["threshold"] else None

    def apply_batch(self, events, z_threshold=4.0, warmup=24):
        t0 = time.perf_counter()
        fresh = [e for e in events if e["event_id"] not in self.seen]
        dups = len(events) - len(fresh)
        # data-health profile: null rate of e-mail on contact change events
        con_ev = [e for e in fresh if e["object"] == "Contact" and e["op"] == "update"]
        rate = (sum(1 for e in con_ev if not (e["record"].get("Email") or e["record"].get("Email__c")))
                / len(con_ev)) if con_ev else 0.0
        alarm = False
        if len(self.profile) >= warmup and len(con_ev) >= 20:
            mu = statistics.mean(self.profile)
            sd = statistics.pstdev(self.profile) or 1e-6
            alarm = (rate - mu) / sd > z_threshold
        if alarm:                      # circuit breaker: hold whole batch for review
            self.held.append([e["event_id"] for e in fresh])
            for e in fresh:
                self.seen.add(e["event_id"])
            return dict(events=len(events), duplicates_skipped=dups, applied=0, rejected=0,
                        held=len(fresh), alarm=True, null_rate=rate,
                        seconds=time.perf_counter() - t0)
        self.profile.append(rate)
        applied = rejected = 0
        with self.con:
            for e in fresh:
                self.seen.add(e["event_id"])
                org, obj, raw = e["org"], e["object"], e["record"]
                if e["op"] == "delete":
                    self.con.execute("DELETE FROM opportunity WHERE sid=?", (raw["Id"],))
                    self.opps.pop(raw["Id"], None)
                    applied += 1; self.applied_event_ids.add(e["event_id"]); continue
                r = transform_record(org, obj, raw)
                bad = [i[0] for i in r["issues"]]
                if obj == "Contact" and (not r.get("LastName") or not r["email_valid"]):
                    bad.append("contact_rule")
                if obj in ("Contact", "Opportunity") and r.get("AccountId") not in self.acc_x:
                    bad.append("parent_not_in_target")
                if obj == "Opportunity" and (r.get("Amount") is None or r["Amount"] < 0):
                    bad.append("negative_amount")
                if obj == "Account" and r["src_id"] not in self.acc_x:
                    bad.append("account_not_in_target")
                if obj == "Contact" and e["op"] == "update" and r["src_id"] not in self.con_x:
                    bad.append("contact_not_in_target")
                if bad:
                    rejected += 1
                    self.audit.append(dict(event_id=e["event_id"], src_id=r["src_id"], rules=bad))
                    continue
                if obj == "Account":
                    self.members[r["src_id"]] = r
                    self._upsert_account(self.acc_x[r["src_id"]])
                elif obj == "Contact":
                    acc_gid = self.acc_x[r["AccountId"]]
                    if r["src_id"] in self.con_x:
                        gid = self.con_x[r["src_id"]]
                    else:
                        gid = self._match_contact(r, acc_gid)
                        if gid is None:
                            gid = f"GCON{self.next_con:08d}"; self.next_con += 1
                            self.con_by_acc[acc_gid].add(gid)
                        self.con_x[r["src_id"]] = gid
                        self.clusters[gid].add(r["src_id"])
                        self.con.execute("INSERT OR REPLACE INTO crosswalk VALUES (?,?,?,?)",
                                         (r["src_id"], org, "Contact", gid))
                    self.members[r["src_id"]] = r
                    if r.get("k_email"):
                        self.email_idx.setdefault(r["k_email"], gid)
                    parent = self.con.execute("SELECT account_gid FROM contact WHERE gid=?", (gid,)).fetchone()
                    self._upsert_contact(gid, parent[0] if parent else acc_gid)
                else:
                    self.opps[r["src_id"]] = r
                    self.con.execute("""INSERT INTO opportunity VALUES (?,?,?,?,?,?,?,?)
                        ON CONFLICT(sid) DO UPDATE SET amount=excluded.amount, stage=excluded.stage,
                        last_modified=excluded.last_modified""",
                                     (r["src_id"], self.acc_x[r["AccountId"]], r["Name"], r["Amount"],
                                      r["StageName"], r["CloseDate"], r["CreatedDate"],
                                      r["LastModifiedDate"]))
                applied += 1
                self.applied_event_ids.add(e["event_id"])
        return dict(events=len(events), duplicates_skipped=dups, applied=applied, rejected=rejected,
                    held=0, alarm=False, null_rate=rate, seconds=time.perf_counter() - t0)


def final_snapshot(src, batches, held_ids, out_dir):
    """Baseline sources plus every delivered event except those the circuit breaker
    held (rejected events still change the source system; held ones are quarantined)."""
    src = copy.deepcopy(src)
    held = set(held_ids)
    seen = set()
    for b in batches:
        for e in b["events"]:
            if e["event_id"] in seen or e["event_id"] in held:
                continue
            seen.add(e["event_id"])
            k = (e["org"], e["object"])
            if e["op"] == "delete":
                src[k].pop(e["record"]["Id"], None)
            else:
                src[k][e["record"]["Id"]] = e["record"]
    os.makedirs(out_dir, exist_ok=True)
    for (org, obj), rows in src.items():
        with open(os.path.join(out_dir, f"org{org}_{obj}.jsonl"), "w") as fh:
            for r in rows.values():
                fh.write(json.dumps(r) + "\n")
    return out_dir


def compare_states(inc_db, full_db):
    """Field-level and cluster-level agreement between incremental and rebuilt targets."""
    def state(con):
        xw = dict(con.execute("SELECT src_id, gid FROM crosswalk WHERE object='Contact'"))
        rows = {r[0]: r[1:] for r in con.execute(
            "SELECT gid, first_name, last_name, email, phone, title FROM contact")}
        acc = {r[0]: r[1:] for r in con.execute("SELECT gid, name, phone, industry FROM account")}
        axw = dict(con.execute("SELECT src_id, gid FROM crosswalk WHERE object='Account'"))
        opp = dict((r[0], r[1:]) for r in con.execute("SELECT sid, amount, stage FROM opportunity"))
        return xw, rows, axw, acc, opp
    ix, ir, iax, ia, io = state(inc_db)
    fx, fr, fax, fa, fo = state(full_db)
    common = set(ix) & set(fx)
    con_same = sum(1 for s in common if ir.get(ix[s]) == fr.get(fx[s]))
    acommon = set(iax) & set(fax)
    acc_same = sum(1 for s in acommon if ia.get(iax[s]) == fa.get(fax[s]))
    opp_same = sum(1 for s in set(io) & set(fo) if io[s] == fo[s])
    # cluster agreement on contacts (pairwise, full rebuild as reference)
    from math import comb
    from collections import Counter
    pairs = Counter((ix[s], fx[s]) for s in common)
    tp = sum(comb(c, 2) for c in pairs.values())
    pi = sum(comb(c, 2) for c in Counter(ix[s] for s in common).values())
    pf = sum(comb(c, 2) for c in Counter(fx[s] for s in common).values())
    return dict(contact_sources_compared=len(common), contact_field_agreement=con_same / len(common),
                account_sources_compared=len(acommon), account_field_agreement=acc_same / len(acommon),
                opportunities_incremental=len(io), opportunities_full=len(fo),
                opportunity_set_equal=set(io) == set(fo),
                opportunity_value_agreement=opp_same / max(1, len(set(io) & set(fo))),
                contact_cluster_pair_precision=tp / pi if pi else 1.0,
                contact_cluster_pair_recall=tp / pf if pf else 1.0)
