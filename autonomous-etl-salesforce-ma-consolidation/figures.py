import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
S=json.load(open('results/summary.json')); R=json.load(open('results/results.json'))
C=["#2a78d6","#eb6834","#1baf7a","#eda100","#e87ba4"]
INK="#2b2b2b"; MUTED="#6b6b6b"; GRID="#e6e6e3"
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":10,"axes.edgecolor":MUTED,
  "axes.labelcolor":INK,"xtick.color":MUTED,"ytick.color":MUTED,"axes.spines.top":False,
  "axes.spines.right":False,"axes.grid":True,"grid.color":GRID,"grid.linewidth":0.8,"axes.axisbelow":True})
OUT="../manuscript/figures/"
# Fig 2 stage time by scale
stages=["extract","transform","validate","mdm","load"]; names=["Extract","Transform","Validate","Match & merge (MDM)","Load"]
fig,ax=plt.subplots(figsize=(7.2,3.4))
labels=[f"{s['source_records']/1000:.0f}k records" for s in S['scaling']]
left=[0]*3
for i,(st,nm) in enumerate(zip(stages,names)):
    v=[s['timings'][st] for s in S['scaling']]
    ax.barh(labels,v,left=left,color=C[i],label=nm,edgecolor="white",linewidth=2,height=0.55)
    left=[a+b for a,b in zip(left,v)]
for y,(l,s) in enumerate(zip(left,S['scaling'])):
    ax.text(l+0.6,y,f"{s['total']:.1f} s  ({s['throughput']:,.0f} rec/s)",va="center",color=INK,fontsize=9)
ax.set_xlabel("Wall-clock seconds (median of 3 runs, 2 CPU cores)"); ax.set_xlim(0,max(left)*1.35)
ax.grid(axis="y",visible=False); ax.legend(ncol=3,frameon=False,loc="upper center",bbox_to_anchor=(0.5,-0.22),fontsize=8.5)
fig.tight_layout(); fig.savefig(OUT+"fig2_stage_times.png",dpi=200); plt.close(fig)
# Fig 3 threshold sweep
th=[0.70,0.75,0.80,0.85,0.90,0.95]
fig,axs=plt.subplots(1,2,figsize=(7.2,3.1),sharey=True)
for ax,obj in zip(axs,("Account","Contact")):
    for j,(k,nm,mk) in enumerate((("precision","Precision","o"),("recall","Recall","s"),("f1","F1","^"))):
        y=[S['mdm'][f"{obj}.sweep.{t}.{k}"][0] for t in th]
        ax.plot(th,y,color=C[j],lw=2,marker=mk,ms=6,label=nm)
    ax.axvline(0.85,color=MUTED,ls="--",lw=1); ax.text(0.853,0.47,"default τ",color=MUTED,fontsize=8)
    ax.set_title(f"{obj}s",color=INK,fontsize=10); ax.set_xlabel("Fuzzy match threshold τ")
    ax.set_ylim(0.45,1.02); ax.set_xticks(th)
axs[0].set_ylabel("Pairwise score (mean of 5 seeds)")
axs[1].legend(frameon=False,loc="center right",bbox_to_anchor=(1.0,0.62),fontsize=8.5)
fig.tight_layout(); fig.savefig(OUT+"fig3_threshold_sweep.png",dpi=200); plt.close(fig)
# Fig 4 CDC null-rate profile
pb=R['cdc']['per_batch']
x=list(range(1,len(pb)+1)); y=[p['null_rate']*100 for p in pb]
fig,ax=plt.subplots(figsize=(7.2,2.8))
ax.plot(x,y,color=C[0],lw=2,marker="o",ms=3)
a=[i for i,p in enumerate(pb) if p['alarm']][0]
ax.plot([a+1],[y[a]],marker="o",ms=9,color=C[1],markeredgecolor="white",markeredgewidth=2,linestyle="none")
ax.annotate("Injected upstream fault detected;\nbatch held by circuit breaker",xy=(a+1,y[a]),xytext=(a+9,70),
            fontsize=8.5,color=INK,arrowprops=dict(arrowstyle="-",color=MUTED))
ax.axvspan(0.5,24.5,color="#f0f0ee",zorder=0); ax.text(1,88,"warm-up (baseline profile)",fontsize=8,color=MUTED)
ax.set_xlabel("Hourly micro-batch (5 simulated days)"); ax.set_ylabel("Contact updates with\nblank e-mail (%)")
ax.set_ylim(-3,105); ax.set_xlim(0,len(pb)+1)
fig.tight_layout(); fig.savefig(OUT+"fig4_cdc_profile.png",dpi=200); plt.close(fig)
print("ok")
