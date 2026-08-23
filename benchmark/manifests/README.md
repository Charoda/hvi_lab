# Batch Manifests

Pre-defined batch configurations for `mosaic batch --manifest <file>`.

| Manifest | Purpose | Size |
|----------|---------|------|
| `starter.batch.json` | Quick sanity check (1 chain) | ~5 min |
| `submission-smoke.batch.json` | Cross-app smoke test | ~30 min |
| `v2-dataset.batch.json` | Curated 72-chain subset of the full 199-chain release (representative spread across apps and CWEs) | ~8 hours |

## Usage

```bash
mosaic manifest validate benchmark/manifests/starter.batch.json
mosaic batch --manifest benchmark/manifests/starter.batch.json
```

## Format

```json
{
  "manifest_version": 1,
  "kind": "mosaic.batch",
  "name": "starter-codex",
  "selection": { "subset": "starter" },
  "execution": {
    "models": ["codex"],
    "output": "benchmark/results/validation/starter_codex.jsonl",
    "warm": true
  },
  "apps": { "tasks_dir": "benchmark/apps" }
}
```

CLI flags override manifest values when specified.
