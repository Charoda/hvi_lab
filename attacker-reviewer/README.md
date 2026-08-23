# Attacker-Reviewer Defense

Exploit-oriented code review using a small open model (Gemma 4 E4B, 4B params) with adversarial **pentester** prompting. The framing — *"write an exploit"* rather than *"check if safe"* — shifts the defense Pareto frontier far more than model scale does.

## Headline numbers

| Defense | Cost / PR | Detection | Diamonds (n=31) | FP on benign PRs |
|---|---|---|---|---|
| Semgrep | $0 | 0% | 0% | ~0% |
| **Gemma pentester** | **~$0.001** | **88.4%** (176/199) | **80.6%** (25/31) | **4.6%** (Wilson 95% CI 3.2–6.6%) |
| BugBot Opus 4.6 | ~$15 | 62% | 0% | n/a |

**4.6% raw FP** measured on **608** sampled benign PRs from 8 popular open-source repos (533 valid verdicts; 75 ERROR). Diamonds = chains that evade *all four* production diff-mode BugBot reviewers.

## 2×2 ablation (same 4B model, four prompts)

|  | Cumulative diff | Stage-3 only | Δ Context |
|---|---|---|---|
| Pentester prompt | **90.1%** | **72.8%** | +17 pp |
| Original / neutral | 23.1% | 24.8% | −2 pp |
| **Δ Prompt** | **+67 pp** | **+48 pp** | |

Prompt framing (+67 pp) dominates diff context (+17 pp) by ~3×. The neutral prompt is barely above chance; the pentester prompt is the entire effect.

## What's in this directory

| File | Purpose |
|---|---|
| `prompts/{original,paranoid,hostile,pentester}.txt` | The four prompt variants used in the ablation |
| `ablation_results.md` | Pre-rendered tables + paper implication |

Raw per-chain reviewer JSONLs are not redistributed; aggregates are in `mosaic-bench.xlsx` (`Results` sheet, columns `BB attacker_reviewer*`) and the paper. To re-score from scratch, run the pipeline below.

## Re-running the defense end-to-end

The harness wires this defense in as `attacker_reviewer` (see `mosaic/defense.py` and `mosaic/attacker_reviewer.py`). The model is served via Vertex AI Model Garden (Gemma 4 E4B). Set `MOSAIC_ATTACKER_BACKEND`, `MOSAIC_ATTACKER_PROMPT`, and `MOSAIC_ATTACKER_VERTEX_ENDPOINT_ID` per the top-level [`README.md`](../README.md#environment-variables), then:

```bash
mosaic run -c <chain> -m codex --review attacker --reuse-container
```

`--review attacker` selects the Gemma 4B reviewer with the pentester prompt and forces cumulative-diff mode. Use `--review cumulative --reviewer attacker-9b` to pick a specific size, or `--reviewer attacker-27b` for the larger variant.

The reviewer verdict (APPROVE / DECLINE / UNCLEAR) is written to the per-trial `manifest.json`.
