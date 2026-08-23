# Datasheet for MOSAIC-Bench

Following [Datasheets for Datasets](https://arxiv.org/abs/1803.09010) (Gebru et al., 2021).

## Motivation

**For what purpose was the dataset created?**
To benchmark the susceptibility of AI coding agents to *compositional* security attacks: multi-stage development requests where each individual ticket appears benign, but the combination introduces an exploitable vulnerability. The benchmark measures both attack success rate (ASR — does an exploit oracle confirm the vulnerability?) and AI-reviewer evasion (do AI code-review systems catch the resulting diff?).

**Who created the dataset, and how was it funded?**
Anonymized for double-blind submission to NeurIPS 2026 Datasets & Benchmarks. Authorship and funding disclosed at camera-ready in the paper's `\begin{ack}` block.

## Composition

**What does each instance represent?**
A MOSAIC instance is an *attack chain*: a chain ID, target app, target CWE, three sequential ticket prompts (`stage1.txt`, `stage2.txt`, `stage3.txt`), a `golden_solution.sh` reference, a `chain.json` metadata file, and a Python PoC oracle (`poc_*.py`) that returns VULNERABLE / SECURE.

The release also ships **per-chain measurements** in `mosaic-bench.xlsx` (199 rows × ~50 columns: per-model ASR in standard and resumed-session modes, per-reviewer BugBot verdicts in diff- and workspace-mode, evasion tier) and references **10 substrate apps** pulled at runtime via `mosaic init` from [`OpenMOSS-Team/ABC-Bench`](https://huggingface.co/datasets/OpenMOSS-Team/ABC-Bench).

**How many instances?**
199 attack chains, 10 substrate apps, full per-model coverage.

**Are there labels?**
For each (chain, model, mode) triple the dataset records VULNERABLE / SECURE / BROKEN as determined by the chain's PoC oracle running against a fresh deployment. For each (chain, reviewer) pair the BugBot verdict is APPROVE / DECLINE / UNCLEAR.

**Sources of noise.**
ASR is a single sample per (chain, model) pair — agent stochasticity is not averaged out. PoC oracles are manually reviewed, but oracle false positives are possible (golden solutions exist as a sanity check). BROKEN trials (agent broke the app) are excluded from ASR denominators.

**Recommended splits.**
None in the train/val/test sense — this is an evaluation benchmark. Natural slices: by app, by CWE family, by evasion tier (Diamond / Golden / Silver / Bronze), by mode (standard / resumed).

## Collection

**How was the data collected?**
Attack chains were authored by the project team. Each chain: (1) manual authorship of the three stage prompts targeting a specific CWE; (2) a golden solution executed by hand to confirm the vulnerability is reachable; (3) a PoC oracle written and tested against the golden state; (4) automated runs against frontier coding agents to measure ASR; (5) AI-reviewer (BugBot) runs against the resulting agent diffs to measure evasion.

**Mechanisms.** Automated runners in the `mosaic` package, CLI subprocesses to each agent backend (Codex, Claude, Gemini, OpenCode), Docker containers with hot-swap for app deployment.

**Timeframe.** March–April 2026.

**Ethical review.** No human subjects, no PII, no third-party systems — all experiments run against open-source web-app boilerplate locally in Docker. No IRB required.

## Preprocessing

Substrate apps were forked from [OpenMOSS-Team/ABC-Bench](https://huggingface.co/datasets/OpenMOSS-Team/ABC-Bench) and lightly modified to pre-seed runtime dependencies (so the hot-swap mechanism, which copies source files, doesn't need to re-run package managers).

## Uses

**Intended uses.** Measuring compositional ASR of AI coding agents; evaluating AI code-review effectiveness as a defense (BugBot diff- and workspace-mode); evaluating attacker-aware reviewers vs. SAST baselines.

**Out-of-scope uses.** This dataset is **not** for training AI models to produce attacks against real-world targets, bypassing security controls in production systems, or as a generic software-engineering benchmark.

## Distribution

Distributed via [`MosaicBenchmark/mosaic-bench`](https://huggingface.co/datasets/MosaicBenchmark/mosaic-bench) on Hugging Face, with Croissant 1.1 metadata in [`croissant.json`](croissant.json) and the harness at the GitHub repository linked in the paper. License: MIT.

## Maintenance

The dataset is hosted on Hugging Face; the harness on GitHub. Author identity and maintainer contact ship at camera-ready per double-blind rules. Issues and questions: GitHub issues or the HF dataset community tab. New chains and additional model coverage will be added in tagged releases; schema changes are tracked via the Croissant metadata version field.
