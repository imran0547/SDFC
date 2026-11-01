"""Reference implementation of the autonomous ETL pipeline.

Stages: partitioned extraction -> template-driven transformation -> quality
gates -> master data management (deterministic + blocked fuzzy matching,
survivorship) -> constrained load with per-record error capture.
"""
from __future__ import annotations

import gzip
import json
import os
import sqlite3
import time
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor

import numpy as np
from rapidfuzz.distance import JaroWinkler
from rapidfuzz.process import cdist

from . import normalize as N
from .templates import (MATCH_CONFIG, PICKLIST_MAPS, SOURCE_PRIORITY, TEMPLATE_VERSION,
                        TEMPLATES)

OBJECTS = ("Account", "Contact", "Opportunity")
STAGES = ("Prospecting", "Qualification", "Proposal", "Negotiation", "Closed Won", "Closed Lost")
INDUSTRIES = ("Technology", "Finance", "Healthcare", "Manufacturing", "Retail", "Energy",
              "Education", "Other")
WORKERS = 2
LOAD_BATCH = 10_000


# ----------------------------------------------------------------------------- extract
def _extract_shard(args):
    org, obj, shard_key, rows, stage_dir = args
    path = os.path.join(stage_dir, org, obj, f"part-{shard_key}.jsonl.gz")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with gzip.open(path, "wt") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    return org, obj, path, len(rows)


def _shard_key(rec):
    v = rec.get("CreatedDate") or rec.get("Created__c") or ""
    if len(v) >= 7 and v[4] == "-":
        return v[:4]                       # ISO -> year partition
    if len(v) >= 10 and v[2] == "/":
        return v[6:10] if v[6:10].isdigit() else "unknown"
    return "unknown"


def extract(data_dir, stage_dir):
    """Partition each source object by creation year and stage shards in parallel."""
    tasks = []
    for org in ("A", "B"):
        for obj in OBJECTS:
            shards = defaultdict(list)
            with open(os.path.join(data_dir, f"org{org}_{obj}.jsonl")) as fh:
                for line in fh:
                    r = json.loads(line)
                    shards[_shard_key(r)].append(r)
            for k, rows in shards.items():
                tasks.append((org, obj, k, rows, stage_dir))
    manifest = []
    with ProcessPoolExecutor(WORKERS) as ex:
        for org, obj, path, n in ex.map(_extract_shard, tasks):
            manifest.append(dict(org=org, object=obj, path=path, records=n))
    return manifest


# --------------------------------------------------------------------------- transform
def transform_record(org, obj, r):
    t = TEMPLATES[org]
    spec = t[obj]
    out = {"src_id": r["Id"], "org": org, "object": obj, "issues": []}
    for canon, field in spec["fields"].items():
        out[canon] = r.get(field)
    for canon, mapname in spec["picklists"].items():
        v = out.get(canon)
        if mapname is not None and v is not None:
            mapped = PICKLIST_MAPS[mapname].get(v)
            if mapped is None:
                out["issues"].append(("unmapped_picklist", canon, v))
            out[canon] = mapped
    for f in ("CreatedDate", "LastModifiedDate"):
        out[f] = N.parse_datetime(out.get(f), t["datetime_format"], t.get("timezone"))
        if out[f] == "INVALID":
            out["issues"].append(("unparseable_date", f, r.get(spec["fields"][f])))
            out[f] = None
    if obj == "Opportunity":
        out["CloseDate"] = N.parse_date(out.get("CloseDate"), t["date_format"])
        if out["CloseDate"] == "INVALID":
            out["issues"].append(("unparseable_date", "CloseDate", None))
            out["CloseDate"] = None
    # normalised match keys
    if obj == "Account":
        out["k_name"] = N.company(out.get("Name"))
        out["k_city"] = (out.get("City") or "").lower() or None
        out["k_phone"] = N.phone(out.get("Phone"))
        out["k_domain"] = N.domain(out.get("Website"))
        out["Website"] = out["k_domain"]
        out["Phone"] = out["k_phone"]
    elif obj == "Contact":
        e, ok = N.email(out.get("Email"))
        out["Email"] = e
        out["email_valid"] = ok
        out["k_email"] = e if ok else None
        out["k_first"] = N.first_name(out.get("FirstName"))
        out["k_last"] = N.person(out.get("LastName"))
        out["k_phone"] = N.phone(out.get("Phone"))
        out["Phone"] = out["k_phone"]
    return out


def _transform_shard(entry):
    rows = []
    with gzip.open(entry["path"], "rt") as fh:
        for line in fh:
            rows.append(transform_record(entry["org"], entry["object"], json.loads(line)))
    return rows


def transform(manifest):
    out = {o: [] for o in OBJECTS}
    with ProcessPoolExecutor(WORKERS) as ex:
        for entry, rows in zip(manifest, ex.map(_transform_shard, manifest, chunksize=4)):
            out[entry["object"]].extend(rows)
    return out


# ---------------------------------------------------------------------------- validate
def validate(recs, enabled=True):
    """Quality gates. Returns accepted records per object and an audit log."""
    audit = []
    accepted = {o: [] for o in OBJECTS}

    def reject(r, rule, field, action="quarantine"):
        audit.append(dict(src_id=r["src_id"], org=r["org"], object=r["object"],
                          rule=rule, field=field, action=action))

    if not enabled:
        for o in OBJECTS:
            accepted[o] = list(recs[o])
        return accepted, audit, {"source_account_ids": set(), "accepted_account_ids": set()}

    all_acc = {r["src_id"] for r in recs["Account"]}
    for r in recs["Account"]:
        bad = False
        for rule, field, _ in r["issues"]:
            reject(r, rule, field); bad = True
        if not r.get("Name"):
            reject(r, "missing_required", "Name"); bad = True
        if not bad:
            accepted["Account"].append(r)
    ok_acc = {r["src_id"] for r in accepted["Account"]}
    # statistical profiling gate (non-blocking): robust outlier fence on log revenue
    import math
    vals = sorted(math.log10(r["AnnualRevenue"]) for r in accepted["Account"]
                  if r.get("AnnualRevenue"))
    if vals:
        q1, q3 = vals[len(vals) // 4], vals[3 * len(vals) // 4]
        fence = q3 + 1.5 * (q3 - q1)
        for r in accepted["Account"]:
            if r.get("AnnualRevenue") and math.log10(r["AnnualRevenue"]) > fence:
                reject(r, "revenue_outlier", "AnnualRevenue", "flag_for_review")

    def parent_check(r):
        a = r.get("AccountId")
        if a not in all_acc:
            reject(r, "orphan_reference", "AccountId"); return False
        if a not in ok_acc:
            reject(r, "parent_quarantined", "AccountId", "hold_until_parent_released"); return False
        return True

    for r in recs["Contact"]:
        bad = False
        for rule, field, _ in r["issues"]:
            reject(r, rule, field); bad = True
        if not r.get("LastName"):
            reject(r, "missing_required", "LastName"); bad = True
        if not r["email_valid"]:
            reject(r, "invalid_email", "Email"); bad = True
        if not parent_check(r):
            bad = True
        if not bad:
            accepted["Contact"].append(r)

    for r in recs["Opportunity"]:
        bad = False
        for rule, field, _ in r["issues"]:
            reject(r, rule, field); bad = True
        if r.get("Amount") is None or r["Amount"] < 0:
            reject(r, "negative_amount", "Amount"); bad = True
        if not parent_check(r):
            bad = True
        if not bad:
            accepted["Opportunity"].append(r)
    return accepted, audit, {"source_account_ids": all_acc, "accepted_account_ids": ok_acc}


# --------------------------------------------------------------------------------- MDM
class UnionFind:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, x):
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra != rb:
            self.p[max(ra, rb)] = min(ra, rb)


def _weighted(parts, weights):
    num = den = 0.0
    for k, v in parts.items():
        if v is not None:
            num += weights[k] * v
            den += weights[k]
    return num / den if den else 0.0


def _eq(a, b):
    if a is None or b is None:
        return None
    return 1.0 if a == b else 0.0


def account_candidates(accs, blocking=True, block_cap=4000):
    """Deterministic pairs and scored fuzzy candidate pairs for accounts."""
    det = set()
    by_dom = defaultdict(list)
    by_name_phone = defaultdict(list)
    for i, r in enumerate(accs):
        if r["k_domain"]:
            by_dom[r["k_domain"]].append(i)
        if r["k_name"] and r["k_phone"]:
            by_name_phone[(r["k_name"], r["k_phone"])].append(i)
    for grp in list(by_dom.values()) + list(by_name_phone.values()):
        for j in grp[1:]:
            det.add((grp[0], j))

    w = MATCH_CONFIG["Account"]["weights"]
    blocks = defaultdict(list)
    if blocking:
        for i, r in enumerate(accs):
            n = r["k_name"] or ""
            if n:
                blocks[("p", n[:4])].append(i)
                toks = n.split()
                blocks[("t", max(toks, key=len)[:5])].append(i)
            if r["k_phone"]:
                blocks[("ph", r["k_phone"])].append(i)
    else:
        blocks[("all",)] = list(range(len(accs)))
    scored = {}
    compared = 0
    for idx in blocks.values():
        if len(idx) < 2:
            continue
        if len(idx) > block_cap:
            idx = idx[:block_cap]
        names = [accs[i]["k_name"] or "" for i in idx]
        sim = cdist(names, names, scorer=JaroWinkler.normalized_similarity,
                    dtype=np.float32, workers=WORKERS, score_cutoff=0.75)
        compared += len(idx) * (len(idx) - 1) // 2
        ii, jj = np.nonzero(np.triu(sim, 1))
        for a, b in zip(ii.tolist(), jj.tolist()):
            i, j = idx[a], idx[b]
            key = (i, j) if i < j else (j, i)
            if key in scored:
                continue
            ri, rj = accs[i], accs[j]
            s = _weighted({"name": float(sim[a, b]), "city": _eq(ri["k_city"], rj["k_city"]),
                           "phone": _eq(ri["k_phone"], rj["k_phone"]),
                           "domain": _eq(ri["k_domain"], rj["k_domain"])}, w)
            scored[key] = s
    return det, scored, compared


def _first_sim(a, b):
    if a is None or b is None:
        return None
    if len(a) == 1 or len(b) == 1:            # initial vs full name
        return 0.9 if a[0] == b[0] else 0.0
    return JaroWinkler.normalized_similarity(a, b)


def contact_candidates(cons, acc_gid_of, blocking=True):
    det = set()
    by_email = defaultdict(list)
    for i, r in enumerate(cons):
        if r["k_email"]:
            by_email[r["k_email"]].append(i)
    for grp in by_email.values():
        for j in grp[1:]:
            det.add((grp[0], j))
    w = MATCH_CONFIG["Contact"]["weights"]
    blocks = defaultdict(list)
    for i, r in enumerate(cons):
        g = acc_gid_of.get(r["AccountId"])
        if blocking:
            if r["k_last"]:
                blocks[(g, "l", r["k_last"][:2])].append(i)
            if r["k_first"]:
                blocks[(g, "f", r["k_first"][:2])].append(i)
            if r["k_phone"]:
                blocks[("ph", r["k_phone"])].append(i)
        else:
            blocks[(g,)].append(i)
    scored = {}
    compared = 0
    for idx in blocks.values():
        n = len(idx)
        compared += n * (n - 1) // 2
        for x in range(n):
            ri = cons[idx[x]]
            for y in range(x + 1, n):
                i, j = idx[x], idx[y]
                key = (i, j) if i < j else (j, i)
                if key in scored:
                    continue
                rj = cons[j]
                ls = JaroWinkler.normalized_similarity(ri["k_last"], rj["k_last"]) \
                    if ri["k_last"] and rj["k_last"] else None
                s = _weighted({"first": _first_sim(ri["k_first"], rj["k_first"]), "last": ls,
                               "email": _eq(ri["k_email"], rj["k_email"]),
                               "phone": _eq(ri["k_phone"], rj["k_phone"])}, w)
                scored[key] = s
    return det, scored, compared


def cluster(n, det, scored, threshold, mode="hybrid"):
    uf = UnionFind(n)
    if mode in ("hybrid", "deterministic"):
        for a, b in det:
            uf.union(a, b)
    if mode in ("hybrid", "fuzzy"):
        for (a, b), s in scored.items():
            if s >= threshold:
                uf.union(a, b)
    return [uf.find(i) for i in range(n)]


def survivorship(records, labels, fields, prefix):
    """Golden record per cluster: latest non-null value per field, acquirer breaks ties."""
    groups = defaultdict(list)
    for r, l in zip(records, labels):
        groups[l].append(r)
    golden, xwalk = {}, {}
    for n, (l, members) in enumerate(sorted(groups.items())):
        gid = f"{prefix}{n:08d}"
        ordered = sorted(members, key=lambda r: (r.get("LastModifiedDate") or "",
                                                 -SOURCE_PRIORITY[r["org"]]), reverse=True)
        g = {"gid": gid}
        for f in fields:
            g[f] = next((m[f] for m in ordered if m.get(f) not in (None, "")), None)
        g["CreatedDate"] = min((m["CreatedDate"] for m in members if m.get("CreatedDate")),
                               default=None)
        g["sources"] = [m["src_id"] for m in members]
        golden[gid] = g
        for m in members:
            xwalk[m["src_id"]] = gid
    return golden, xwalk


ACC_FIELDS = ("Name", "City", "State", "Phone", "Website", "Industry", "AnnualRevenue",
              "LastModifiedDate")
CON_FIELDS = ("FirstName", "LastName", "Email", "Phone", "Title", "LastModifiedDate")


def mdm(accepted, mode="hybrid", acc_threshold=None, con_threshold=None, blocking=True,
        acc_cands=None):
    acc_threshold = acc_threshold or MATCH_CONFIG["Account"]["threshold"]
    con_threshold = con_threshold or MATCH_CONFIG["Contact"]["threshold"]
    accs, cons = accepted["Account"], accepted["Contact"]
    t0 = time.perf_counter()
    det_a, sc_a, cmp_a = acc_cands or account_candidates(accs, blocking)
    acc_labels = cluster(len(accs), det_a, sc_a, acc_threshold, mode)
    acc_golden, acc_x = survivorship(accs, acc_labels, ACC_FIELDS, "GACC")
    t1 = time.perf_counter()
    det_c, sc_c, cmp_c = contact_candidates(cons, acc_x, blocking)
    con_labels = cluster(len(cons), det_c, sc_c, con_threshold, mode)
    con_golden, con_x = survivorship(cons, con_labels, CON_FIELDS, "GCON")
    con_parent = {}                                   # re-parent to golden account
    for c, l in zip(cons, con_labels):
        con_parent.setdefault(con_x[c["src_id"]], acc_x.get(c["AccountId"], c["AccountId"]))
    for gid, g in con_golden.items():
        g["AccountGid"] = con_parent[gid]
    t2 = time.perf_counter()
    return dict(acc_golden=acc_golden, acc_x=acc_x, acc_labels=acc_labels,
                con_golden=con_golden, con_x=con_x, con_labels=con_labels,
                acc_cands=(det_a, sc_a, cmp_a),
                stats=dict(acc_pairs_compared=cmp_a, acc_candidates=len(sc_a),
                           acc_det_pairs=len(det_a), con_pairs_compared=cmp_c,
                           con_candidates=len(sc_c), con_det_pairs=len(det_c),
                           t_acc=t1 - t0, t_con=t2 - t1))


# -------------------------------------------------------------------------------- load
SCHEMA = f"""
PRAGMA foreign_keys = ON;
CREATE TABLE account(gid TEXT PRIMARY KEY, name TEXT NOT NULL, city TEXT, state TEXT,
  phone TEXT, website TEXT,
  industry TEXT CHECK (industry IS NULL OR industry IN {INDUSTRIES}),
  annual_revenue INTEGER, created TEXT NOT NULL, last_modified TEXT);
CREATE TABLE contact(gid TEXT PRIMARY KEY, account_gid TEXT REFERENCES account(gid),
  first_name TEXT, last_name TEXT NOT NULL,
  email TEXT CHECK (email IS NULL OR (email LIKE '%_@_%._%' AND email NOT LIKE '%@%@%')),
  phone TEXT, title TEXT, created TEXT NOT NULL, last_modified TEXT);
CREATE TABLE opportunity(sid TEXT PRIMARY KEY,
  account_gid TEXT NOT NULL REFERENCES account(gid), name TEXT,
  amount INTEGER CHECK (amount >= 0), stage TEXT CHECK (stage IN {STAGES}),
  close_date TEXT, created TEXT NOT NULL, last_modified TEXT);
CREATE TABLE crosswalk(src_id TEXT PRIMARY KEY, org TEXT, object TEXT, gid TEXT);
CREATE TABLE audit(src_id TEXT, org TEXT, object TEXT, rule TEXT, field TEXT, action TEXT);
CREATE TABLE load_error(object TEXT, key TEXT, error TEXT);
"""


def connect(path):
    if os.path.exists(path):
        os.remove(path)
    con = sqlite3.connect(path)
    con.executescript(SCHEMA)
    return con


def _bulk(con, sql, rows, obj, key_idx=0):
    """Insert in fixed-size batches; on failure, retry row by row and capture errors
    (mirrors per-record result handling of a bulk API job)."""
    ok = err = 0
    for s in range(0, len(rows), LOAD_BATCH):
        batch = rows[s:s + LOAD_BATCH]
        try:
            with con:
                con.executemany(sql, batch)
            ok += len(batch)
        except sqlite3.IntegrityError:
            for row in batch:
                try:
                    with con:
                        con.execute(sql, row)
                    ok += 1
                except sqlite3.IntegrityError as e:
                    err += 1
                    con.execute("INSERT INTO load_error VALUES (?,?,?)", (obj, row[key_idx], str(e)))
    con.commit()
    return ok, err


def load(con, m, accepted, audit):
    t = {}
    acc_rows = [(g["gid"], g["Name"], g["City"], g["State"], g["Phone"], g["Website"],
                 g["Industry"], g["AnnualRevenue"], g["CreatedDate"], g["LastModifiedDate"])
                for g in m["acc_golden"].values()]
    con_rows = [(g["gid"], g["AccountGid"], g["FirstName"], g["LastName"], g["Email"], g["Phone"],
                 g["Title"], g["CreatedDate"], g["LastModifiedDate"])
                for g in m["con_golden"].values()]
    opp_rows = [(r["src_id"], m["acc_x"].get(r["AccountId"], r["AccountId"]), r["Name"],
                 r["Amount"], r["StageName"], r["CloseDate"], r["CreatedDate"],
                 r["LastModifiedDate"]) for r in accepted["Opportunity"]]
    res = {}
    t0 = time.perf_counter()
    res["Account"] = _bulk(con, "INSERT INTO account VALUES (?,?,?,?,?,?,?,?,?,?)", acc_rows, "Account")
    res["Contact"] = _bulk(con, "INSERT INTO contact VALUES (?,?,?,?,?,?,?,?,?)", con_rows, "Contact")
    res["Opportunity"] = _bulk(con, "INSERT INTO opportunity VALUES (?,?,?,?,?,?,?,?)", opp_rows, "Opportunity")
    t["load"] = time.perf_counter() - t0
    xw = [(s, s[3], "Account", g) for s, g in m["acc_x"].items()] + \
         [(s, s[3], "Contact", g) for s, g in m["con_x"].items()]
    with con:
        con.executemany("INSERT INTO crosswalk VALUES (?,?,?,?)", xw)
        con.executemany("INSERT INTO audit VALUES (?,?,?,?,?,?)",
                        [(a["src_id"], a["org"], a["object"], a["rule"], a["field"], a["action"])
                         for a in audit])
    return res, t["load"]


# ---------------------------------------------------------------------------- reconcile
def reconcile(con, recs, accepted, audit):
    """Source-to-target reconciliation: every source record is either represented in the
    target (directly or via a golden record) or accounted for in the audit log."""
    q = {o: {a["src_id"] for a in audit if a["object"] == o} for o in OBJECTS}
    xw = {r[0] for r in con.execute("SELECT src_id FROM crosswalk")}
    opp_target = {r[0] for r in con.execute("SELECT sid FROM opportunity")}
    out = {}
    for o in OBJECTS:
        ids = {r["src_id"] for r in recs[o]}
        represented = (ids & opp_target) if o == "Opportunity" else (ids & xw)
        out[o] = dict(source=len(ids), represented=len(represented), quarantined=len(ids & q[o]),
                      unaccounted=len(ids - represented - q[o]))
    fk_orphans = con.execute("""SELECT
        (SELECT COUNT(*) FROM contact c LEFT JOIN account a ON c.account_gid=a.gid
           WHERE c.account_gid IS NOT NULL AND a.gid IS NULL) +
        (SELECT COUNT(*) FROM opportunity o LEFT JOIN account a ON o.account_gid=a.gid
           WHERE a.gid IS NULL)""").fetchone()[0]
    amount_src = sum(r["Amount"] for r in accepted["Opportunity"])
    amount_tgt = con.execute("SELECT COALESCE(SUM(amount),0) FROM opportunity").fetchone()[0]
    out["fk_orphans_in_target"] = fk_orphans
    out["opportunity_amount_checksum_match"] = (amount_src == amount_tgt)
    return out


# --------------------------------------------------------------------------------- run
def run_batch(data_dir, work_dir, validation=True, mode="hybrid", acc_threshold=None,
              con_threshold=None, blocking=True):
    os.makedirs(work_dir, exist_ok=True)
    timings = {}
    t = time.perf_counter()
    manifest = extract(data_dir, os.path.join(work_dir, "staging"))
    timings["extract"] = time.perf_counter() - t
    t = time.perf_counter()
    recs = transform(manifest)
    timings["transform"] = time.perf_counter() - t
    t = time.perf_counter()
    accepted, audit, _ = validate(recs, validation)
    timings["validate"] = time.perf_counter() - t
    t = time.perf_counter()
    m = mdm(accepted, mode, acc_threshold, con_threshold, blocking)
    timings["mdm"] = time.perf_counter() - t
    con = connect(os.path.join(work_dir, "target.db"))
    load_res, timings["load"] = load(con, m, accepted, audit)
    rec = reconcile(con, recs, accepted, audit)
    n_src = sum(len(v) for v in recs.values())
    return dict(recs=recs, accepted=accepted, audit=audit, mdm=m, con=con, manifest=manifest,
                metrics=dict(template_version=TEMPLATE_VERSION, source_records=n_src,
                             shards=len(manifest), timings=timings,
                             total_seconds=sum(timings.values()),
                             load=load_res, reconcile=rec, mdm_stats=m["stats"],
                             golden_accounts=len(m["acc_golden"]),
                             golden_contacts=len(m["con_golden"])))
