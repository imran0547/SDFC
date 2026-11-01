import warnings,pickle,json;warnings.filterwarnings("ignore")
import pandas as pd, pm4py
d=pickle.load(open("prep.pkl","rb")); M=pickle.load(open("out/models.pkl","rb"))
df,cases=d["df"],d["cases"]; CID="case:concept:name"
test=df[df[CID].isin(d["test"])]
ids=list(test.groupby(CID).groups.keys())
won=(cases.loc[ids,"outcome"]=="won").values
rows=[]
for t,c in M["soft"].items():
    for k,v in c.items():
        res=pm4py.conformance_declare(test,{t:{k:v}})
        viol=pd.Series([r["no_dev_total"]>0 for r in res])
        act=pd.Series([r["no_constr_total"]>0 for r in res]) if "no_constr_total" in res[0] else None
        rows.append(dict(template=t,args=" , ".join(k) if isinstance(k,tuple) else k,
            train_conf=round(v["confidence"]/v["support"],3),
            test_violation=round(viol.mean(),4), n_viol=int(viol.sum()),
            win_if_viol=round(won[viol.values].mean(),3) if viol.sum() else None,
            win_if_ok=round(won[~viol.values].mean(),3)))
R=pd.DataFrame(rows).sort_values("n_viol",ascending=False)
print(res[0].keys())
print(R.head(25).to_string())
R.to_csv("out/soft_rules.csv",index=False)
pos=["init","exactly_one","existence","precedence","succession","altsuccession","chainsuccession","altresponse","response","chainresponse","coexistence","responded_existence","altprecedence"]
H=[(t,k,v) for t,c in M["hard"].items() if t in pos for k,v in c.items()]
print(len(H))
for t,k,v in sorted(H,key=lambda x:-x[2]["support"]):
    if t!="altprecedence": print(t,k,v["support"])
