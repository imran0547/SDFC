import json, statistics as st
R=json.load(open('results/results.json'))
def ms(xs): return (st.mean(xs), st.stdev(xs) if len(xs)>1 else 0.0)
S={}
S['env']=R['environment']
S['scaling']=[]
for s in R['scaling']:
    m=s['median']; t=m['timings']
    S['scaling'].append(dict(entities=s['n_accounts_entities'], source_records=m['source_records'],
        summary=s['summary'], runs=s['total_seconds_runs'], timings=t, total=m['total_seconds'],
        throughput=m['source_records']/m['total_seconds'], golden_acc=m['golden_accounts'],
        golden_con=m['golden_contacts'], shards=m['shards'], load=m['load'], reconcile=m['reconcile'],
        mdm_stats=m['mdm_stats']))
Q=R['quality']
S['quality_summary']=Q[0]['summary']
agg={}
for obj in ('Account','Contact'):
    for k in ('precision','recall','f1'):
        agg[f'{obj}.{k}']=ms([q['mdm'][obj][k] for q in Q])
    for mode in ('deterministic','fuzzy','hybrid'):
        for k in ('precision','recall','f1'):
            agg[f'{obj}.{mode}.{k}']=ms([q['modes'][mode][obj][k] for q in Q])
    for t in Q[0]['sweep']:
        for k in ('precision','recall','f1'):
            agg[f'{obj}.sweep.{t}.{k}']=ms([q['sweep'][t][obj][k] for q in Q])
    agg[f'{obj}.true_pairs']=ms([q['mdm'][obj]['true_pairs'] for q in Q])
    agg[f'{obj}.records']=ms([q['mdm'][obj]['records'] for q in Q])
S['mdm']=agg
# validation
defs=sorted({d for q in Q for d in q['validation']['per_defect']})
val={}
for d in defs:
    inj=sum(q['validation']['per_defect'].get(d,{}).get('injected',0) for q in Q)
    det=sum(q['validation']['per_defect'].get(d,{}).get('detected',0) for q in Q)
    val[d]=dict(injected=inj, detected=det, recall=det/inj)
S['validation']=dict(per_defect=val,
    cascade=sum(q['validation']['cascade_holds'] for q in Q),
    fp=sum(q['validation']['false_positives'] for q in Q),
    clean=sum(q['validation']['clean_records'] for q in Q),
    injected_records=sum(q['validation']['total_injected_records'] for q in Q),
    detected_records=sum(q['validation']['total_detected_records'] for q in Q),
    records=sum(q['metrics']['source_records'] for q in Q))
S['gate']=dict(with_gate_load_errors=[sum(v[1] for v in q['metrics']['load'].values()) for q in Q],
    no_gate_load_errors=[q['no_gate']['load_errors'] for q in Q],
    no_gate_by_object=[q['no_gate']['load'] for q in Q],
    with_gate_fk=[q['metrics']['reconcile']['fk_orphans_in_target'] for q in Q],
    no_gate_fk=[q['no_gate']['fk_orphans'] for q in Q],
    reconcile=[q['metrics']['reconcile'] for q in Q])
S['blocking']=R['blocking_ablation_accounts_2000']
c=dict(R['cdc']); c.pop('per_batch')
S['cdc']=c
pb=R['cdc']['per_batch']
S['cdc_extra']=dict(alarm_batch=[p for p in pb if p['alarm']], max_normal_null=max(p['null_rate'] for p in pb if not p['alarm']),
   mean_normal_null=st.mean(p['null_rate'] for p in pb if not p['alarm']))
json.dump(S,open('results/summary.json','w'),indent=1)
print(json.dumps(S,indent=1)[:12000])
