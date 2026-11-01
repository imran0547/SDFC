"""Runs every experiment reported in the paper and writes results/results.json.

    python run_experiments.py            # full study
    python run_experiments.py --quick    # small smoke version
"""
import json
import os
import platform
import shutil
import statistics
import sys
import time

from sfsim import cdc
from sfsim.evaluate import mdm_quality, pairwise_prf, validation_quality
from sfsim.generate import generate
from sfsim.pipeline import account_candidates, cluster, mdm, run_batch

QUICK = "--quick" in sys.argv
ROOT = "/tmp/sfsim_runs"
OUT = "results"
os.makedirs(OUT, exist_ok=True)
SCALES = [2000, 5000] if QUICK else [5000, 20000, 60000]
QUALITY_N = 2000 if QUICK else 10000
SEEDS = [7, 8] if QUICK else [7, 8, 9, 10, 11]
CDC_N = 2000 if QUICK else 20000
THRESHOLDS = [0.70, 0.75, 0.80, 0.85, 0.90, 0.95]

results = {"environment": {"python": platform.python_version(), "machine": platform.machine(),
                           "cpus_used": 2, "platform": platform.platform()}}


def data(n, seed):
    d = f"{ROOT}/data_{n}_{seed}"
    if not os.path.exists(os.path.join(d, "truth.json")):
        generate(n, d, seed)
    return d, json.load(open(os.path.join(d, "truth.json"))), json.load(open(os.path.join(d, "summary.json")))


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# ---------------------------------------------------------------- E1 scaling / throughput
results["scaling"] = []
for n in SCALES:
    d, truth, summ = data(n, 7)
    runs = []
    for rep in range(3):
        r = run_batch(d, f"{ROOT}/work_scale_{n}")
        runs.append(r["metrics"])
        r["con"].close()
    med = sorted(runs, key=lambda m: m["total_seconds"])[1]
    results["scaling"].append(dict(n_accounts_entities=n, summary=summ,
                                   total_seconds_runs=[m["total_seconds"] for m in runs],
                                   median=med))
    log("scale", n, summ["total_source_records"], [round(m["total_seconds"], 1) for m in runs])

# ------------------------------------------------- E2/E3 quality across seeds + ablations
qual = []
for seed in SEEDS:
    d, truth, summ = data(QUALITY_N, seed)
    r = run_batch(d, f"{ROOT}/work_q_{seed}")
    row = dict(seed=seed, summary=summ, metrics=r["metrics"],
               mdm=mdm_quality(r["accepted"], r["mdm"], truth),
               validation=validation_quality(r["recs"], r["audit"], truth))
    # matching strategy ablation on the same accepted records
    cands = r["mdm"]["acc_cands"]
    row["modes"] = {}
    for mode in ("deterministic", "fuzzy", "hybrid"):
        mm = mdm(r["accepted"], mode=mode, acc_cands=cands)
        row["modes"][mode] = mdm_quality(r["accepted"], mm, truth)
    row["sweep"] = {}
    for t in THRESHOLDS:
        mm = mdm(r["accepted"], mode="hybrid", acc_threshold=t, con_threshold=t, acc_cands=cands)
        row["sweep"][str(t)] = mdm_quality(r["accepted"], mm, truth)
    r["con"].close()
    # validation-gate ablation
    r2 = run_batch(d, f"{ROOT}/work_nogate_{seed}", validation=False)
    row["no_gate"] = dict(load=r2["metrics"]["load"],
                          load_errors=sum(v[1] for v in r2["metrics"]["load"].values()),
                          fk_orphans=r2["metrics"]["reconcile"]["fk_orphans_in_target"])
    r2["con"].close()
    qual.append(row)
    log("quality seed", seed, row["mdm"]["Account"]["f1"], row["mdm"]["Contact"]["f1"])
results["quality"] = qual

# --------------------------------------------------------------- blocking ablation (small)
d, truth, _ = data(2000, 7)
r = run_batch(d, f"{ROOT}/work_blk")
blk = {}
for name, b in (("blocking", True), ("no_blocking", False)):
    t0 = time.perf_counter()
    det, sc, cmp_ = account_candidates(r["accepted"]["Account"], blocking=b)
    labels = cluster(len(r["accepted"]["Account"]), det, sc, 0.85)
    blk[name] = dict(pairs_compared=cmp_, seconds=time.perf_counter() - t0,
                     quality=pairwise_prf([x["src_id"] for x in r["accepted"]["Account"]], labels, truth))
r["con"].close()
results["blocking_ablation_accounts_2000"] = blk
log("blocking", blk["blocking"]["pairs_compared"], blk["no_blocking"]["pairs_compared"])

# ---------------------------------------------------------------------------- E4 CDC
d, truth, summ = data(CDC_N, 7)
truth = dict(truth)
work = f"{ROOT}/work_cdc"
shutil.rmtree(work, ignore_errors=True)
base = run_batch(d, work)
src = cdc.load_sources(d)
batches = cdc.generate_events(src, truth, days=5, change_rate=0.02, dup_rate=0.01)
sync = cdc.IncrementalSync(base)
per_batch = []
for b in batches:
    res = sync.apply_batch(b["events"])
    res.update(day=b["day"], hour=b["hour"], injected_anomaly=b["anomalous"])
    per_batch.append(res)
held_ids = [i for h in sync.held for i in h]
snap = cdc.final_snapshot(src, batches, held_ids, f"{ROOT}/data_cdc_final")
full = run_batch(snap, f"{ROOT}/work_cdc_full")
eq = cdc.compare_states(sync.con, full["con"])
# post-CDC contact matching quality vs truth (incremental state)
con_ids = list(sync.con_x.keys())
post_inc = pairwise_prf(con_ids, [sync.con_x[s] for s in con_ids], truth)
full_ids = [x["src_id"] for x in full["accepted"]["Contact"]]
post_full = pairwise_prf(full_ids, full["mdm"]["con_labels"], truth)
secs = [p["seconds"] for p in per_batch]
alarms = [(p["day"], p["hour"]) for p in per_batch if p["alarm"]]
injected = [(p["day"], p["hour"]) for p in per_batch if p["injected_anomaly"]]
results["cdc"] = dict(
    summary=summ, days=5, batches=len(batches), schedule="hourly micro-batches",
    events_delivered=sum(p["events"] for p in per_batch),
    duplicates_skipped=sum(p["duplicates_skipped"] for p in per_batch),
    applied=sum(p["applied"] for p in per_batch), rejected=sum(p["rejected"] for p in per_batch),
    held=sum(p["held"] for p in per_batch),
    batch_seconds=dict(mean=statistics.mean(secs), median=statistics.median(secs),
                       p95=sorted(secs)[int(0.95 * len(secs)) - 1], max=max(secs)),
    events_per_batch_mean=statistics.mean(p["events"] for p in per_batch),
    alarms=alarms, injected_anomalies=injected,
    false_alarms=len([a for a in alarms if a not in injected]),
    equivalence=eq, post_cdc_contact_quality_incremental=post_inc,
    post_cdc_contact_quality_full_rebuild=post_full,
    full_rebuild_seconds=full["metrics"]["total_seconds"],
    per_batch=per_batch)
log("cdc", results["cdc"]["applied"], results["cdc"]["alarms"], eq)

with open(os.path.join(OUT, "results.json"), "w") as fh:
    json.dump(results, fh, indent=1, default=str)
log("done")
