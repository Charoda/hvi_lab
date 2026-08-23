# Local results ledger (optional)

This directory is for **your own local re-run results**. The public release does **not** ship a populated ledger — headline ASR / BugBot tables live in `mosaic-bench.xlsx` and the paper. That's why `mosaic doctor` warns about a missing `manifest.json`. The warning is informational, not an error.

You only need to create a `manifest.json` here if:

- you want `mosaic validate` and `benchmark.validation.ledger` to cross-check your local re-runs against the workbook, or
- you want a stable index of multiple local result files (canonical / validation / archive).

## Schema

Copy `manifest.json.template` to `manifest.json` and edit:

```json
{
  "kind": "mosaic.results",
  "manifest_version": 1,
  "dataset_workbook": "mosaic-bench.xlsx",
  "coverage": "partial",
  "active": [
    {
      "path": "canonical/local_codex.jsonl",
      "label": "local-codex",
      "purpose": "Codex 5.3 re-run, 199 chains"
    }
  ],
  "validation": [],
  "archive_root": "archive"
}
```

- `coverage`: `"partial"` (subset) or `"complete"` (all 199 × all models).
- `active[]` / `validation[]`: each entry's `path` is relative to this directory; `label` and `purpose` are free-form.
- `archive_root`: optional subdir for older runs.

## Generating local results

```bash
# One model, one chain
mosaic run -c express_mark_modified -m codex --reuse-container

# One model, the curated 72-chain subset
python3 scripts/mosaic_eval.py --model codex --output canonical/local_codex.jsonl

# Then point manifest.json at canonical/local_codex.jsonl and re-run:
mosaic doctor    # results_manifest check should now go from warn → ok
mosaic validate  # cross-checks ledger against the workbook
```

## What's tracked vs. ignored

- `README.md` and `manifest.json.template` are tracked.
- Everything else under `benchmark/results/` is gitignored — your local runs stay local.
