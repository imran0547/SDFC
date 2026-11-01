"""Declarative CRM automation experiment on BPI Challenge 2012.
Outputs results.json and figures in /tmp/work/out/."""
import warnings, pickle, json, random, time, os
warnings.filterwarnings("ignore")
import numpy as np, pandas as pd
import pm4py
from scipy.stats import chi2_contingency

OUT = "/tmp/work/out"; os.makedirs(OUT, exist_ok=True)
random.seed(42); np.random.seed(42)
d = pickle.load(open("/tmp/work/prep.pkl", "rb"))
df, cases = d["df"], d["cases"]
CID, ACT, TS = "case:concept:name", "concept:name", "time:timestamp"
train = df[df[CID].isin(d["train"])].copy()
test = df[df[CID].isin(d["test"])].copy()
R = {"data": {"raw_events": d["raw"], "complete_events": len(df), "cases": len(cases),
              "closed_cases": len(d["train"]) + len(d["test"]),
              "train_cases": len(d["train"]), "test_cases": len(d["test"]),
              "train_events": len(train), "test_events": len(test),
              "activities": int(df[ACT].nunique()),
              "resources": int(df["org:resource"].nunique()),
              "outcomes": cases["outcome"].value_counts().to_dict(),
              "variants_closed": int(df[df[CID].isin(d["train"] | d["test"])]
                                     .groupby(CID)[ACT].apply(tuple).nunique()),
              "period": [str(df[TS].min().date()), str(df[TS].max().date())]}}

# ---------------- 1. discovery ----------------
t0 = time.time()
raw = pm4py.discover_declare(train, min_support_ratio=0.1, min_confidence_ratio=0.95)
R["discovery_seconds"] = round(time.time() - t0, 1)
n_tr = len(d["train"])

def count(m): return sum(len(v) for v in m.values())
R["raw_constraints"] = count(raw)
R["raw_by_template"] = {k: len(v) for k, v in raw.items()}

# ---------------- 2. refinement ----------------
act_freq = train.groupby(ACT)[CID].nunique() / n_tr
def copy(m): return {k: dict(v) for k, v in m.items()}

def step_negative(m, min_freq=0.10):
    """Drop negative constraints between activities that are each rare:
    they hold trivially and carry no business meaning."""
    m = copy(m)
    for t in ["noncoexistence", "nonsuccession", "nonchainsuccession"]:
        for k in list(m.get(t, {})):
            if min(act_freq.get(k[0], 0), act_freq.get(k[1], 0)) < min_freq:
                del m[t][k]
    # noncoexistence is symmetric: keep one direction
    seen = set()
    for k in list(m.get("noncoexistence", {})):
        key = frozenset(k)
        if key in seen: del m["noncoexistence"][k]
        else: seen.add(key)
    return m

IMPLIES = {  # stronger -> weaker (same argument order)
    "chainsuccession": ["chainresponse", "chainprecedence", "altsuccession", "succession"],
    "altsuccession": ["altresponse", "altprecedence", "succession"],
    "succession": ["response", "precedence", "coexistence"],
    "chainresponse": ["altresponse", "response", "responded_existence"],
    "chainprecedence": ["altprecedence", "precedence"],
    "altresponse": ["response", "responded_existence"],
    "altprecedence": ["precedence"],
    "response": ["responded_existence"],
    "nonsuccession": ["nonchainsuccession"],
}
def closure(t):
    out, stack = set(), list(IMPLIES.get(t, []))
    while stack:
        x = stack.pop()
        if x not in out: out.add(x); stack += IMPLIES.get(x, [])
    return out

def step_subsumption(m):
    m = copy(m)
    for t in list(m):
        for k in list(m[t]):
            for w in closure(t):
                m.get(w, {}).pop(k, None)
    # succession-family rules imply coexistence in either argument order
    for t in ["succession", "altsuccession", "chainsuccession"]:
        for k in list(m.get(t, {})):
            m.get("coexistence", {}).pop(k, None); m.get("coexistence", {}).pop((k[1], k[0]), None)
    # coexistence(a,b) implies responded_existence both ways; dedupe symmetric coexistence
    for k in list(m.get("coexistence", {})):
        m.get("responded_existence", {}).pop(k, None)
        m.get("responded_existence", {}).pop((k[1], k[0]), None)
    seen = set()
    for k in list(m.get("coexistence", {})):
        if frozenset(k) in seen: del m["coexistence"][k]
        else: seen.add(frozenset(k))
    # noncoexistence(a,b) implies nonsuccession in both directions
    for k in list(m.get("noncoexistence", {})):
        for kk in [k, (k[1], k[0])]:
            m.get("nonsuccession", {}).pop(kk, None); m.get("nonchainsuccession", {}).pop(kk, None)
    # exactly_one(a) implies existence(a)
    for k in list(m.get("exactly_one", {})):
        m.get("existence", {}).pop(k, None)
    # init(a) implies existence(a)
    for k in list(m.get("init", {})):
        m.get("existence", {}).pop(k, None)
    return m

def step_transitive(m):
    """Remove response/precedence/responded_existence edges implied by a 2-step chain."""
    m = copy(m)
    for t in ["response", "precedence", "responded_existence"]:
        edges = set(m.get(t, {}))
        # strong edges of same semantics that can form chains
        strong = edges | set(m.get("succession", {})) | set(m.get("altsuccession", {})) \
                 | set(m.get("chainsuccession", {}))
        if t == "response":
            strong |= set(m.get("altresponse", {})) | set(m.get("chainresponse", {}))
        if t == "precedence":
            strong |= set(m.get("altprecedence", {})) | set(m.get("chainprecedence", {}))
        for (a, c) in list(edges):
            mids = {b for (x, b) in strong if x == a and b != c}
            if any((b, c) in strong for b in mids):
                m[t].pop((a, c), None)
    return m

case_sets = train.groupby(CID)[ACT].apply(set)
def cooc(a, b): return float(case_sets.map(lambda s: a in s and b in s).mean())
_cooc = {}
def step_vacuity(m, min_cooc=0.10):
    """Negative ordering rules are only informative when both activities
    actually co-occur in a meaningful share of cases."""
    m = copy(m)
    for t in ["nonsuccession", "nonchainsuccession"]:
        for k in list(m.get(t, {})):
            key = frozenset(k)
            if key not in _cooc: _cooc[key] = cooc(*k)
            if _cooc[key] < min_cooc: del m[t][k]
    return m

m1 = step_negative(raw)
m2 = step_subsumption(m1)
m3 = step_transitive(m2)
m4 = step_vacuity(m3)
R["refinement"] = [
    {"step": "Raw discovery (support>=0.10, confidence>=0.95)", "constraints": count(raw)},
    {"step": "R1: remove trivial negative constraints", "constraints": count(m1)},
    {"step": "R2: remove subsumed (implied) constraints", "constraints": count(m2)},
    {"step": "R3: remove transitively redundant constraints", "constraints": count(m3)},
    {"step": "R4: remove vacuous negative ordering constraints", "constraints": count(m4)},
]
refined = {k: v for k, v in m4.items() if v}

# hard (confidence = 100% on training) vs soft rules
hard = {t: {k: v for k, v in c.items() if v["confidence"] == v["support"]} for t, c in refined.items()}
hard = {t: c for t, c in hard.items() if c}
soft = {t: {k: v for k, v in c.items() if v["confidence"] < v["support"]} for t, c in refined.items()}
soft = {t: c for t, c in soft.items() if c}
R["refined_by_template"] = {k: len(v) for k, v in refined.items()}
R["hard_constraints"] = count(hard); R["soft_constraints"] = count(soft)

def rows(m, kind):
    out = []
    for t, c in m.items():
        for k, v in c.items():
            out.append({"template": t, "args": list(k) if isinstance(k, tuple) else [k],
                        "support": v["support"], "confidence": v["confidence"],
                        "conf_ratio": round(v["confidence"] / v["support"], 4), "kind": kind})
    return out
R["refined_list"] = sorted(rows(hard, "hard") + rows(soft, "soft"),
                           key=lambda r: (-r["support"], r["template"]))

# ---------------- 3. conformance on held-out test ----------------
def declare_conf(log, model):
    res = pm4py.conformance_declare(log, model)
    fit = np.array([r["dev_fitness"] for r in res])
    full = np.array([r["no_dev_total"] == 0 for r in res])
    return fit, full

def summarize(log, model, name):
    fit, full = declare_conf(log, model)
    return {"model": name, "constraints": count(model),
            "mean_constraint_fitness": round(float(fit.mean()), 4),
            "fully_compliant_cases": round(float(full.mean()), 4)}

R["conformance"] = [summarize(test, raw, "Raw"), summarize(test, refined, "Refined (all)"),
                    summarize(test, hard, "Refined: hard rules"),
                    summarize(test, soft, "Refined: soft rules")]
R["conformance_train"] = [summarize(train, refined, "Refined (all)"),
                          summarize(train, hard, "Refined: hard rules")]

# ---------------- 4. procedural baseline ----------------
def petri_stats(net):
    return len(net.places), len(net.transitions), len(net.arcs)

baselines = {}
for noise in [0.0, 0.2]:
    net, im, fm = pm4py.discover_petri_net_inductive(train, noise_threshold=noise)
    baselines[f"Inductive Miner (noise={noise})"] = (net, im, fm)
net_h, im_h, fm_h = pm4py.discover_petri_net_heuristics(train, dependency_threshold=0.9)
baselines["Heuristics Miner (dep=0.9)"] = (net_h, im_h, fm_h)

R["baseline"] = []
for name, (net, im, fm) in baselines.items():
    fit = pm4py.fitness_token_based_replay(test, net, im, fm)
    prec = pm4py.precision_token_based_replay(test, net, im, fm)
    p, tr_, a = petri_stats(net)
    R["baseline"].append({"model": name, "places": p, "transitions": tr_, "arcs": a,
                          "size": p + tr_ + a,
                          "log_fitness": round(fit["log_fitness"], 4),
                          "fit_traces_pct": round(fit["perc_fit_traces"] / 100, 4),
                          "precision": round(prec, 4)})

# ---------------- 5. negative traces: discrimination ----------------
acts_all = sorted(df[ACT].unique())
test_cases = test.groupby(CID)
sample_ids = random.sample(list(d["test"]), 1000)
neg_rows = []
for cid in sample_ids:
    g = test_cases.get_group(cid).sort_values(TS)
    seq = list(g[ACT]); ts = list(g[TS])
    for op in ["swap", "delete", "insert"]:
        s = seq.copy()
        if op == "swap" and len(s) > 2:
            i = random.randrange(len(s) - 1); s[i], s[i + 1] = s[i + 1], s[i]
        elif op == "delete" and len(s) > 1:
            del s[random.randrange(len(s))]
        elif op == "insert":
            s.insert(random.randrange(len(s) + 1), random.choice(acts_all))
        if s == seq: continue
        t = pd.date_range("2020-01-01", periods=len(s), freq="min", tz="UTC")
        for a, tt in zip(s, t):
            neg_rows.append({CID: f"{cid}_{op}", ACT: a, TS: tt})
neg = pd.DataFrame(neg_rows)
pos = test[test[CID].isin(sample_ids)][[CID, ACT, TS]]
R["negatives"] = {"n_positive": len(sample_ids), "n_negative": int(neg[CID].nunique())}

def petri_accept(log, net, im, fm):
    diag = pm4py.conformance_diagnostics_token_based_replay(log, net, im, fm)
    return np.array([x["trace_is_fit"] for x in diag])

disc = []
for name, model in [("Declarative refined: hard rules", hard), ("Declarative refined: all rules", refined)]:
    _, fp = declare_conf(pos, model); _, fn = declare_conf(neg, model)
    disc.append({"model": name, "accept_positive": round(float(fp.mean()), 4),
                 "reject_negative": round(float(1 - fn.mean()), 4)})
for name, (net, im, fm) in baselines.items():
    ap = petri_accept(pm4py.convert_to_event_log(pos), net, im, fm)
    an = petri_accept(pm4py.convert_to_event_log(neg), net, im, fm)
    disc.append({"model": name, "accept_positive": round(float(ap.mean()), 4),
                 "reject_negative": round(float(1 - an.mean()), 4)})
for r in disc:
    r["balanced_accuracy"] = round((r["accept_positive"] + r["reject_negative"]) / 2, 4)
R["discrimination"] = disc

# ---------------- 6. multi-perspective: rules vs sales outcomes ----------------
closed_ids = d["train"] | d["test"]
c = cases.loc[list(closed_ids)].copy()
c["won"] = (c["outcome"] == "won").astype(int)
ev = df[df[CID].isin(closed_ids)]
first = ev.groupby([CID, ACT])[TS].min().unstack()
human = ev[ev["orig"].str.startswith("W_")].groupby(CID)[TS].min()
c["t_first_touch_h"] = ((human - c["start"]).dt.total_seconds() / 3600).reindex(c.index)

# rule A: Response(Proposal Sent -> Follow-up Call (Proposal)) within 7 days
sent = first.get("Proposal Sent")
fu_after = ev[ev[ACT] == "Follow-up Call (Proposal)"][[CID, TS]]
ps = ev[ev[ACT] == "Proposal Sent"].groupby(CID)[TS].min()
fu = fu_after.merge(ps.rename("ps"), left_on=CID, right_index=True)
fu = fu[fu[TS] >= fu["ps"]].groupby(CID)[TS].min()
c["has_proposal"] = c.index.isin(ps.index)
c["fu_delay_d"] = ((fu - ps).dt.total_seconds() / 86400).reindex(c.index)

def rate_table(sub, col, bins, labels):
    sub = sub.copy(); sub["bin"] = pd.cut(sub[col], bins=bins, labels=labels, include_lowest=True)
    t = sub.groupby("bin", observed=False).agg(cases=("won", "size"), win_rate=("won", "mean"))
    t["win_rate"] = t["win_rate"].round(4)
    return t.reset_index().astype({"bin": str}).to_dict("records")

pc = c[c["has_proposal"]]
pc_fill = pc.copy(); pc_fill["fu_delay_d"] = pc_fill["fu_delay_d"].fillna(999)
R["followup_vs_win"] = rate_table(pc_fill, "fu_delay_d", [-0.001, 1, 3, 7, 1000],
                                  ["<=1 day", "1-3 days", "3-7 days", ">7 days"])
R["proposal_cases_without_followup"] = int(pc["fu_delay_d"].isna().sum())
ct = pd.crosstab(pc_fill["fu_delay_d"] <= 7, pc_fill["won"])
chi2, p, _, _ = chi2_contingency(ct)
R["followup_chi2"] = {"chi2": round(chi2, 2), "p": float(p), "n": int(len(pc_fill))}

valid = c.dropna(subset=["t_first_touch_h"])
R["first_touch_vs_win"] = rate_table(valid, "t_first_touch_h", [-0.001, 1, 24, 72, 1e6],
                                     ["<=1 h", "1-24 h", "1-3 days", ">3 days"])
ct2 = pd.crosstab(valid["t_first_touch_h"] <= 24, valid["won"])
chi2b, pb, _, _ = chi2_contingency(ct2)
R["first_touch_chi2"] = {"chi2": round(chi2b, 2), "p": float(pb), "n": int(len(valid))}
R["first_touch_median_h"] = round(float(valid["t_first_touch_h"].median()), 2)

# deal-value segments: win rate and hard-rule compliance (test set)
fit_t, full_t = declare_conf(test, soft)
test_ids_order = list(test.groupby(CID).groups.keys())
comp = pd.Series(full_t, index=test_ids_order)
ct_ = c.loc[c.index.isin(d["test"])].copy(); ct_["compliant"] = comp.reindex(ct_.index)
ct_["segment"] = pd.qcut(ct_["amount"], 4, labels=["Q1 (smallest)", "Q2", "Q3", "Q4 (largest)"])
seg = ct_.groupby("segment", observed=False).agg(cases=("won", "size"),
      amount_min=("amount", "min"), amount_max=("amount", "max"),
      win_rate=("won", "mean"), soft_rule_compliance=("compliant", "mean")).round(4)
wc = ct_.groupby("compliant").agg(cases=("won","size"), win_rate=("won","mean")).round(4)
R["win_by_soft_compliance"] = {str(k): v for k, v in wc.to_dict("index").items()}
ct3 = pd.crosstab(ct_["compliant"], ct_["won"]); c3, p3, _, _ = chi2_contingency(ct3)
R["soft_compliance_chi2"] = {"chi2": round(c3, 2), "p": float(p3), "n": int(len(ct_))}
R["segments"] = seg.reset_index().astype({"segment": str}).to_dict("records")

# resources: follow-up workload concentration
fu_ev = ev[ev[ACT] == "Follow-up Call (Proposal)"]
res = fu_ev.groupby("org:resource").size().sort_values(ascending=False)
R["followup_resources"] = {"n_resources": int(len(res)),
                           "top10_share": round(float(res.head(10).sum() / res.sum()), 4)}

json.dump(R, open(f"{OUT}/results.json", "w"), indent=1, default=str)
pickle.dump({"refined": refined, "hard": hard, "soft": soft}, open(f"{OUT}/models.pkl", "wb"))
print(json.dumps({k: v for k, v in R.items() if k != "refined_list"}, indent=1, default=str))
