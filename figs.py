import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

R = json.load(open("/tmp/work/out/results.json"))
OUT = "/tmp/work/out"
BLUE, ORANGE = "#2a78d6", "#eb6834"
INK, INK2, GRID = "#0b0b0b", "#52514e", "#e4e3df"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.edgecolor": INK2,
                     "axes.labelcolor": INK, "xtick.color": INK2, "ytick.color": INK2,
                     "axes.spines.top": False, "axes.spines.right": False})

def style(ax, grid_axis="x"):
    ax.grid(axis=grid_axis, color=GRID, linewidth=0.8); ax.set_axisbelow(True)

# Fig 4: refinement funnel
steps = R["refinement"]
labels = ["Raw discovery", "R1 Trivial negatives\nremoved", "R2 Subsumed rules\nremoved",
          "R3 Transitive\nredundancy removed", "R4 Vacuous negatives\nremoved"]
vals = [s["constraints"] for s in steps]
fig, ax = plt.subplots(figsize=(7, 3.4))
bars = ax.barh(labels[::-1], vals[::-1], color=BLUE, height=0.6)
for b, v in zip(bars, vals[::-1]):
    ax.text(v + 15, b.get_y() + b.get_height() / 2, f"{v:,}", va="center", color=INK)
ax.set_xlabel("Number of Declare constraints"); style(ax)
ax.set_xlim(0, max(vals) * 1.12)
fig.tight_layout(); fig.savefig(f"{OUT}/fig4_refinement.png", dpi=220); plt.close(fig)

# Fig 5: discrimination grouped bars
D = R["discrimination"]
names = ["Declarative\n(hard rules)", "Declarative\n(all rules)", "Inductive Miner\n(noise 0.0)",
         "Inductive Miner\n(noise 0.2)", "Heuristics Miner\n(dep. 0.9)"]
ap = [r["accept_positive"] * 100 for r in D]; rn = [r["reject_negative"] * 100 for r in D]
import numpy as np
x = np.arange(len(names)); w = 0.36
fig, ax = plt.subplots(figsize=(7.4, 3.8))
b1 = ax.bar(x - w / 2 - 0.01, ap, w, color=BLUE, label="Real test cases accepted")
b2 = ax.bar(x + w / 2 + 0.01, rn, w, color=ORANGE, label="Perturbed (invalid) cases rejected")
for bs in (b1, b2):
    for b in bs:
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 1.2, f"{b.get_height():.0f}",
                ha="center", fontsize=8, color=INK)
ax.set_xticks(x, names, fontsize=8.5); ax.set_ylim(0, 110); ax.set_ylabel("% of cases")
style(ax, "y"); ax.legend(frameon=False, loc="upper center", bbox_to_anchor=(0.5, 1.13), ncol=2)
fig.tight_layout(); fig.savefig(f"{OUT}/fig5_discrimination.png", dpi=220); plt.close(fig)

# Fig 6: follow-up delay vs win rate
F = R["followup_vs_win"]
fig, ax = plt.subplots(figsize=(6.4, 3.3))
lab = [f"{r['bin']}\n(n={r['cases']:,})" for r in F]; v = [r["win_rate"] * 100 for r in F]
bars = ax.bar(lab, v, color=BLUE, width=0.55)
for b in bars:
    ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 1, f"{b.get_height():.1f}%",
            ha="center", color=INK, fontsize=9)
ax.set_ylabel("Deal win rate (%)"); ax.set_xlabel("Time from Proposal Sent to first follow-up call")
ax.set_ylim(0, 75); style(ax, "y")
fig.tight_layout(); fig.savefig(f"{OUT}/fig6_followup.png", dpi=220); plt.close(fig)

# Fig 7: segments - two panels (no dual axis)
S = R["segments"]
seg = [s["segment"].replace(" (", "\n(") for s in S]
fig, axs = plt.subplots(1, 2, figsize=(7.6, 3.2))
for ax, key, title in [(axs[0], "win_rate", "Deal win rate (%)"),
                       (axs[1], "soft_rule_compliance", "Soft-rule compliance (%)")]:
    vals = [s[key] * 100 for s in S]
    bars = ax.bar(seg, vals, color=BLUE, width=0.55)
    for b in bars:
        ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 1, f"{b.get_height():.0f}%",
                ha="center", fontsize=8.5, color=INK)
    ax.set_title(title, fontsize=10, color=INK, loc="left"); ax.set_ylim(0, 100)
    ax.tick_params(axis="x", labelsize=8); style(ax, "y")
fig.supxlabel("Requested amount (deal value) quartile, test set", fontsize=9, color=INK2)
fig.tight_layout(); fig.savefig(f"{OUT}/fig7_segments.png", dpi=220); plt.close(fig)
print("ok")
