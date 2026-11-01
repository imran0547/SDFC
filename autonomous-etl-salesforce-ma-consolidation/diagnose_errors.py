import json, itertools
from collections import defaultdict, Counter
from sfsim.pipeline import run_batch, mdm
d="/tmp/sfsim_runs/data_10000_7"; truth=json.load(open(d+"/truth.json"))
r=run_batch(d,"/tmp/diag")
acc=r["accepted"]["Account"]; con=r["accepted"]["Contact"]
# entity -> canonical name to detect siblings: sibling eid created right after parent; check name stem sharing
def fp_pairs(recs, labels):
    groups=defaultdict(list)
    for x,l in zip(recs,labels): groups[l].append(x)
    out=[]
    for g in groups.values():
        for a,b in itertools.combinations(g,2):
            if truth[a["src_id"]]["entity"]!=truth[b["src_id"]]["entity"]: out.append((a,b))
    return out
def fn_pairs(recs, labels):
    lab={x["src_id"]:l for x,l in zip(recs,labels)}
    ent=defaultdict(list)
    for x in recs: ent[truth[x["src_id"]]["entity"]].append(x)
    out=[]
    for g in ent.values():
        for a,b in itertools.combinations(g,2):
            if lab[a["src_id"]]!=lab[b["src_id"]]: out.append((a,b))
    return out
m_det=mdm(r["accepted"],mode="deterministic",acc_cands=r["mdm"]["acc_cands"])
fp=fp_pairs(acc,m_det["acc_labels"])
same_dom=sum(1 for a,b in fp if a["k_domain"] and a["k_domain"]==b["k_domain"])
stem=sum(1 for a,b in fp if (a["k_name"] or "").split()[:1]==(b["k_name"] or "").split()[:1])
print("det acc FP pairs",len(fp),"same domain",same_dom,"same first token",stem)
m70=mdm(r["accepted"],acc_threshold=0.70,con_threshold=0.70,acc_cands=r["mdm"]["acc_cands"])
fp=fp_pairs(acc,m70["acc_labels"])
stem=sum(1 for a,b in fp if (a["k_name"] or "").split()[:1]==(b["k_name"] or "").split()[:1])
print("tau.70 acc FP pairs",len(fp),"same first token",stem, [ (a["Name"],b["Name"]) for a,b in fp[:8]])
fn=fn_pairs(con,r["mdm"]["con_labels"])
c=Counter()
for a,b in fn:
    c["email_differs_or_missing"]+= (a["k_email"]!=b["k_email"] or a["k_email"] is None)
    c["phone_missing_either"]+= (a["k_phone"] is None or b["k_phone"] is None)
    c["both"]+= ((a["k_email"]!=b["k_email"] or a["k_email"] is None) and (a["k_phone"] is None or b["k_phone"] is None or a["k_phone"]!=b["k_phone"]))
print("contact FN",len(fn),c)
