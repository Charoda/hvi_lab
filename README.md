# HiveTrace / hvi_lab (release)

Slim public tree for the **coding-agent defense harness**: scenarios B01–B20,
permission profiles (`off` / `normal` / `strict`), OpenCode + Cursor runners,
and final audit tables.

This is **not** the full upstream [MOSAIC-Bench](https://github.com/mosaic-benchmark/mosaic-benchmark) corpus.
Upstream ABC chains, classic `mosaic` CLI, attacker-reviewer, and local GGUF tooling were removed.

## What is in git

| Path | Role |
|---|---|
| `isolated/harness/` | Batch runner (`run.sh`), scoring, metrics |
| `isolated/run.py` + agent Docker files | Isolated OpenCode path |
| `isolated/manual_cursor/` | Cursor workspace staging helpers |
| `configs/{cursor,opencode}/` | Permission profiles |
| `benchmark/chains/b*` | Malicious + benign twin scenarios |
| `benchmark/apps/task_myteam_b*` | Scenario substrates |
| `mosaic/deploy.py` (+ small import graph) | App registry used by the harness |
| `audit/final_*.tsv`, `final_stats*`, `build_final_stats.py` | Final matrix + stats |
| `docs/HARNESS.md`, `docs/CHANGELOG.md` | Runbook + changelog |
| `scripts/build_dataset_release.py` | Pack HF dataset locally |

## What is *not* in git

| Artifact | Where |
|---|---|
| `logs/` (~20 GB run evidence) | Local only (gitignored) |
| `dataset_release/` (~1.1 GB pack) | **Hugging Face** — see [`scripts/publish_hf.md`](scripts/publish_hf.md) |
| `.env` secrets | Local only — copy from `.env.example` |

## Quick start

```bash
cp .env.example .env   # set OPENROUTER_API_KEY / CURSOR_API_KEY

# Cursor, one scenario, strict profile
./isolated/harness/run.sh --actor cursor --profile strict --scenarios b07 \
  --model composer-2.5

# OpenCode / Nemotron
./isolated/harness/run.sh --actor opencode --profile off --scenarios b07 \
  --model openrouter/nvidia/nemotron-3-ultra-550b-a55b
```

Pin models explicitly — do **not** use `auto` for reproducible matrix runs.
Details: [`docs/HARNESS.md`](docs/HARNESS.md).

## Dataset

Main matrix: **1200** VALID runs (20 scenarios × malicious/benign × 3 profiles × 2 actors × N=5),
plus a separate 30-run B14 sandbox experiment.

- Audit catalog: `audit/final_runs.tsv`, `audit/final_b14_sandbox.tsv`
- Stats: `audit/final_stats.md`
- Packed logs for HF: build/upload via [`scripts/publish_hf.md`](scripts/publish_hf.md)

## License

See [`LICENSE`](LICENSE).
