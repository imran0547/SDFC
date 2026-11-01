# Declarative Automation in CRM – replication code

Code for the paper "A Framework for Declarative Automation in CRM: Improving Sales Efficiency Using Flow-Oriented Process Engineering".

## Data
BPI Challenge 2012 event log (van Dongen, 2012), https://doi.org/10.4121/uuid:3926db30-f712-4394-aebc-75976070e91f
Save it as `data/bpic2012.xes.gz`, or change the path in `prep.py`.

## Requirements
Python 3.10+, `pip install pm4py scipy matplotlib pandas numpy`, and Graphviz (`dot`) for the diagrams.

## Run
```
python prep.py          # label mapping, outcomes, temporal 70/30 split -> prep.pkl
python experiment.py    # discovery, refinement R1-R4, conformance, baselines, discrimination, outcome analysis -> out/results.json
python soft.py          # per-soft-rule violation and win-rate analysis -> out/soft_rules.csv
python figs.py          # charts (Figures 3, 5, 6, 7)
dot -Tpng -Gdpi=200 fig1.dot -o fig1_framework.png   # same for fig2.dot, fig3.dot
```
Scripts expect a working folder `/tmp/work`; edit the paths at the top of each file if you use a different one. The random seed is fixed at 42, so the discrimination test is reproducible.
