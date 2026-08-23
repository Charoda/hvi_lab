"""Statistical analysis utilities for MOSAIC benchmark results."""

from __future__ import annotations

import math
from collections import defaultdict
from statistics import NormalDist

from .schema import TrialResult


def wilson_ci(successes: int, n: int, confidence: float = 0.95) -> tuple[float, float, float]:
    """Wilson score confidence interval for a binomial proportion.

    Args:
        successes: Number of successes (PASS verdicts).
        n: Total number of trials.
        confidence: Confidence level (default 0.95).

    Returns:
        Tuple of (point_estimate, lower_bound, upper_bound).
    """
    if n == 0:
        return (0.0, 0.0, 0.0)
    z = NormalDist().inv_cdf(1 - (1 - confidence) / 2)
    p_hat = successes / n
    denominator = 1 + z**2 / n
    center = (p_hat + z**2 / (2 * n)) / denominator
    spread = z * math.sqrt((p_hat * (1 - p_hat) + z**2 / (4 * n)) / n) / denominator
    lower = max(0.0, center - spread)
    upper = min(1.0, center + spread)
    return (p_hat, lower, upper)


def compute_asr(
    results: list[TrialResult],
    group_by: str = "model",
) -> list[dict]:
    """Compute Attack Success Rate with Wilson confidence intervals.

    Args:
        results: List of TrialResult objects.
        group_by: Field to group by. One of "model", "task", "workstream",
                  "model_task", or "mechanism".

    Returns:
        List of dicts with keys: group, trials, passes, asr, ci_lower, ci_upper.
    """
    groups: dict[str, list[TrialResult]] = defaultdict(list)

    for r in results:
        if group_by == "model":
            key = r.model
        elif group_by == "task":
            key = r.task
        elif group_by == "workstream":
            key = r.workstream
        elif group_by == "model_task":
            key = f"{r.model}/{r.task}"
        elif group_by == "mechanism":
            key = r.mechanism
        else:
            raise ValueError(f"Unknown group_by: {group_by!r}")
        groups[key].append(r)

    output = []
    for key in sorted(groups):
        trials = groups[key]
        n = len(trials)
        passes = sum(1 for t in trials if t.verdict == "PASS")
        asr, ci_low, ci_high = wilson_ci(passes, n)
        output.append({
            "group": key,
            "trials": n,
            "passes": passes,
            "asr": round(asr, 4),
            "ci_lower": round(ci_low, 4),
            "ci_upper": round(ci_high, 4),
        })

    return output
