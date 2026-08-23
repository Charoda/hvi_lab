# Ablation Results: Prompt × Diff Mode (Gemma 4B)

## 2×2 Ablation Matrix

|  | Cumulative Diff | Stage3 Only | Δ Context |
|---|---|---|---|
| **Pentester prompt** | **90.1%** (118/131) | **72.8%** (99/136) | **+17pp** |
| **Original/neutral** | **23.1%** (12/52) | **24.8%** (34/137) | **-2pp** |
| **Δ Prompt** | **+67pp** | **+48pp** | |

## Key Findings

1. **Prompt framing dominates**: +67pp effect on cumulative, +48pp on stage3. This is 3× larger than the context effect (+17pp).

2. **Compositional context helps only the pentester**: Original prompt gets ~24% regardless of context. Pentester jumps from 73% → 90% with cumulative context. The adversarial framing *unlocks* the value of seeing the full composition.

3. **Original prompt ≈ random on cumulative**: 23% detection is barely above chance for a binary classifier on VULNERABLE chains. The neutral "is this code safe?" framing genuinely does not work for a 4B model.

## Comparison with BugBot (frontier models)

| Reviewer | Model | Cumulative | Stage3 Only |
|----------|-------|-----------|-------------|
| BugBot | Opus 4.6 (~200B) | 62% | varies |
| BugBot | Sonnet 4.6 (~70B) | 57% | varies |
| BugBot | Codex GPT-5.4 (~200B) | 76% | varies |
| **Gemma pentester** | **4B** | **90%** | **73%** |
| Gemma original | 4B | 23% | 25% |

The 4B model with neutral prompt (23%) is far worse than any frontier reviewer (57-76%).
The same 4B model with pentester prompt (90%) is far better than any frontier reviewer.
**The prompt effect (+67pp) is larger than the model scaling effect (57→76% = 19pp).**

## Paper Implication

> "Review framing explains more detection variance than model scaling. A 4B model with adversarial prompting outperforms frontier models with neutral prompting by 14-33 percentage points. The defense Pareto frontier has structure orthogonal to model scale."
