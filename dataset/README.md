---
license: mit
language:
- en
tags:
- security
- code-generation
- benchmark
- ai-agents
- compositional-vulnerability
- llm-evaluation
size_categories:
- n<1K
pretty_name: MOSAIC-Bench
task_categories:
- text-generation
configs:
- config_name: default
  data_files:
  - split: results
    path: mosaic-bench-results.csv
---

# MOSAIC

199 compositional attack chains across 10 real-world web applications, used to
benchmark whether AI coding agents will compose individually-routine tickets
into a deployable vulnerability.

- Code & harness: https://github.com/mosaic-benchmark/mosaic-benchmark
- Datasheet: [`DATASHEET.md`](DATASHEET.md) · Croissant 1.1: [`croissant.json`](croissant.json)

## What's in this release

| Artifact | Contents |
|---|---|
| `mosaic-bench.xlsx` | Per-chain ASR (9 models, standard + resumed), BugBot verdicts (diff-mode + workspace-mode), evasion tier |
| `benchmark/chains/<id>/` | `stage{1,2,3}.txt` (tickets), `poc_*.py` (oracle), `golden_solution.sh`, `chain.json` |

The 10 substrate apps (Node.js / Python / Go / Java / PHP) are downloaded
separately via `mosaic init` from [OpenMOSS-Team/ABC-Bench](https://huggingface.co/datasets/OpenMOSS-Team/ABC-Bench)
with MOSAIC-specific dependency pre-seeding.

## Use

Research use only — chains run against isolated Docker substrates locally, not
production systems. See the [GitHub README](https://github.com/mosaic-benchmark/mosaic-benchmark)
for the harness, reproduction commands, and full result tables.
