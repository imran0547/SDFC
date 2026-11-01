"""Evaluation against ground truth (never visible to the pipeline)."""
from collections import Counter, defaultdict
from math import comb


def pairwise_prf(src_ids, labels, truth):
    """Pairwise precision/recall/F1 of predicted clusters vs true entities."""
    pred = defaultdict(list)
    for s, l in zip(src_ids, labels):
        pred[l].append(truth[s]["entity"])
    true_sizes = Counter(truth[s]["entity"] for s in src_ids)
    tp = sum(comb(c, 2) for members in pred.values() for c in Counter(members).values())
    pp = sum(comb(len(m), 2) for m in pred.values())
    ap = sum(comb(c, 2) for c in true_sizes.values())
    p = tp / pp if pp else 1.0
    r = tp / ap if ap else 1.0
    f = 2 * p * r / (p + r) if p + r else 0.0
    return dict(precision=p, recall=r, f1=f, true_pairs=ap, predicted_pairs=pp, tp=tp,
                records=len(src_ids), true_entities=len(true_sizes), predicted_clusters=len(pred))


def mdm_quality(accepted, m, truth):
    acc_ids = [r["src_id"] for r in accepted["Account"]]
    con_ids = [r["src_id"] for r in accepted["Contact"]]
    return dict(Account=pairwise_prf(acc_ids, m["acc_labels"], truth),
                Contact=pairwise_prf(con_ids, m["con_labels"], truth))


def validation_quality(recs, audit, truth):
    """Detection rate per injected defect type, plus records flagged without an
    injected defect (split into cascade holds and genuine false positives)."""
    flagged = defaultdict(set)
    for a in audit:
        flagged[a["src_id"]].add(a["rule"])
    per = {}
    all_ids = [r["src_id"] for o in recs.values() for r in o]
    injected = Counter()
    detected = Counter()
    for s in all_ids:
        for d in truth[s]["defects"]:
            injected[d] += 1
            if s in flagged:
                detected[d] += 1
    for d in injected:
        per[d] = dict(injected=injected[d], detected=detected[d],
                      recall=detected[d] / injected[d])
    clean_flagged = [s for s in flagged if not truth[s]["defects"]]
    cascade = [s for s in clean_flagged if flagged[s] <= {"parent_quarantined"}]
    fp = [s for s in clean_flagged if not flagged[s] <= {"parent_quarantined"}]
    n_clean = sum(1 for s in all_ids if not truth[s]["defects"])
    return dict(per_defect=per,
                total_injected_records=sum(1 for s in all_ids if truth[s]["defects"]),
                total_detected_records=sum(1 for s in all_ids if truth[s]["defects"] and s in flagged),
                cascade_holds=len(cascade), false_positives=len(fp),
                false_positive_rate=len(fp) / n_clean if n_clean else 0.0,
                clean_records=n_clean)
