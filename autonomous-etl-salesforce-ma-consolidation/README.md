# Autonomous ETL Pipelines for Salesforce M&A Consolidation

Manuscript and reproducibility package for *Autonomous ETL Pipelines for Salesforce M&A Consolidation: A Reference Framework, Jitterbit Mapping and Reproducible Simulation Study*.

Reference prototype of the pipeline described in the paper (extract, template-driven transform,
quality gates, MDM, constrained load, CDC with circuit breaker), plus a synthetic two-org data
generator with ground truth, and the scripts that produce every number and figure in the paper.

## Requirements
Python 3.11+; `pip install rapidfuzz faker numpy matplotlib`

## Reproduce
    python run_experiments.py        # full study (about 12 minutes on 2 cores) -> results/results.json
    python summarize.py              # aggregates across seeds -> results/summary.json
    python figures.py                # figures -> manuscript/figures/
    python diagnose_errors.py        # seed-7 error analysis quoted in Sections 5.1-5.2 and 6 (run after run_experiments.py)
    python run_experiments.py --quick   # small smoke version

## Layout
- `manuscript/`         the paper (.docx), its source (`paper.md`), `build.js` (rebuild with `node build.js`; needs the `docx` npm package) and figures
- `sfsim/generate.py`   synthetic orgs A and B, duplicates, hard negatives, injected defects, truth.json
- `sfsim/templates.py`  declarative mapping templates, picklist maps, match configuration
- `sfsim/normalize.py`  field normalisation and match keys
- `sfsim/pipeline.py`   extract, transform, validate, MDM, load, reconcile
- `sfsim/cdc.py`        change events, idempotent incremental sync, circuit breaker, rebuild comparison
- `sfsim/evaluate.py`   pairwise P/R/F1 and defect detection against ground truth
- `results/`            raw and summarised results used in the paper

The pipeline never reads `truth.json`; only `evaluate.py` and the diagnostics do.
SQLite stands in for the target org, so timings exclude network latency and Salesforce API limits.
