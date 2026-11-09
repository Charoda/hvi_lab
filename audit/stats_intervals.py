#!/usr/bin/env python3
"""Statistical intervals and contrasts for HiveTrace / MOSAIC run matrix.

Reads audit/index.tsv (and hard-failure run_ids from audit/task1_table.md /
task1_final.tsv when available). Writes:

  audit/stats_intervals_pooled.tsv      ASR/IRR/FPR/TCR + Wilson/CP/bootstrap CI
  audit/stats_intervals_by_scenario.tsv per-scenario ASR + Wilson/CP
  audit/stats_intervals_contrasts.tsv   profile contrasts (Fisher + paired perm)
  audit/stats_intervals_report.md       what to use, why, limits / risks

Default denominator = scope B from Task 3 (hard failures excluded).

No third-party deps (stdlib only).
"""
from __future__ import annotations

import argparse
import csv
import math
import random
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
AUDIT = REPO / "audit"
DEFAULT_ALPHA = 0.05
DEFAULT_BOOT = 5000
DEFAULT_PERM = 10000
SEED = 20261020

PROFILES = ("off", "normal", "strict")
ACTORS = ("cursor", "opencode")
PRIMARY_CONTRASTS = (("off", "normal"), ("off", "strict"), ("normal", "strict"))


# ---------------------------------------------------------------------------
# parsing helpers
# ---------------------------------------------------------------------------

def _b(v):
    if v is None or v == "":
        return None
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    if s in ("true", "1", "yes"):
        return True
    if s in ("false", "0", "no"):
        return False
    return None


def _f4(x) -> str:
    if x is None:
        return ""
    return f"{x:.4f}"


def load_index(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def load_exclude_ids(audit: Path, index_ids: set[str]) -> tuple[set[str], str]:
    """Prefer task1_final.tsv flags; fall back to run_ids in task1_table.md.

    Only IDs present in the current index.tsv are kept (stale audit tables from
    older reruns are ignored rather than silently dropping nothing useful).
    """
    final = audit / "task1_final.tsv"
    if final.is_file():
        rows = list(csv.DictReader(final.open(newline="", encoding="utf-8"), delimiter="\t"))
        flagged = {
            r["run_id"]
            for r in rows
            if r.get("exclude_from_metrics") == "True"
            or (r.get("hard_failure") and r["hard_failure"] != "ok")
        }
        flagged &= index_ids
        if flagged:
            return flagged, "task1_final.tsv"

    table = audit / "task1_table.md"
    if table.is_file():
        ids = set(re.findall(r"`([A-Za-z0-9_.:-]+)`", table.read_text(encoding="utf-8")))
        ids = {i for i in ids if re.search(r"20\d{6}-\d{6}", i)}
        matched = ids & index_ids
        if matched:
            return matched, "task1_table.md"
        if ids:
            return set(), f"task1_table.md(stale:{len(ids)}_ids_not_in_index)"

    return set(), "none"


HARD_API = re.compile(
    r"requires more credits|only afford \d+ tokens|adjust the key's total limit"
    r"|AI_APICallError|Rate limit exceeded|free-models-per-day"
    r"|level=ERROR.*\"stream error\""
    r"|\b(500|502|503|504)\b(?=.*(error|Error|gateway|Gateway|unavailable))"
)
HARD_CLI_MODEL = re.compile(r"Cannot use this model")
TIMEOUT_S = 2400.0


def _read_capped(path: Path, limit: int = 2_000_000) -> str:
    try:
        if not path.is_file():
            return ""
        with path.open("r", encoding="utf-8", errors="replace") as fh:
            return fh.read(limit)
    except OSError:
        return ""


def scan_hard_failures(logs: Path, idx: list[dict]) -> set[str]:
    """Content-based hard-failure detection aligned with task1_final.py."""
    out: set[str] = set()
    for r in idx:
        rid = r["run_id"]
        try:
            dur = float(r.get("duration_s") or 0.0)
        except ValueError:
            dur = 0.0
        if dur >= TIMEOUT_S:
            out.add(rid)
            continue
        if r.get("actor") == "opencode":
            blob = _read_capped(logs / rid / "actor_stderr.log") + "\n" + _read_capped(
                logs / rid / "actor_stdout.log"
            )
        else:
            blob = _read_capped(logs / rid / "cursor_agent.log")
        if HARD_API.search(blob) or HARD_CLI_MODEL.search(blob):
            out.add(rid)
    return out


# ---------------------------------------------------------------------------
# binomial primitives (exact, stdlib)
# ---------------------------------------------------------------------------

def _log_binom_pmf(k: int, n: int, p: float) -> float:
    if p <= 0.0:
        return 0.0 if k == 0 else float("-inf")
    if p >= 1.0:
        return 0.0 if k == n else float("-inf")
    return (
        math.lgamma(n + 1)
        - math.lgamma(k + 1)
        - math.lgamma(n - k + 1)
        + k * math.log(p)
        + (n - k) * math.log(1.0 - p)
    )


def binom_cdf(k: int, n: int, p: float) -> float:
    """P(X <= k) for X ~ Binomial(n, p). Sum in log-space from mode outwards."""
    if k < 0:
        return 0.0
    if k >= n:
        return 1.0
    # naive sum is fine for n <= ~200 here
    total = 0.0
    for i in range(0, k + 1):
        total += math.exp(_log_binom_pmf(i, n, p))
    return min(1.0, max(0.0, total))


def binom_sf(k: int, n: int, p: float) -> float:
    """P(X >= k)."""
    if k <= 0:
        return 1.0
    if k > n:
        return 0.0
    return min(1.0, max(0.0, 1.0 - binom_cdf(k - 1, n, p)))


def wilson_ci(k: int, n: int, alpha: float = DEFAULT_ALPHA) -> tuple[float, float]:
    """Wilson score interval (recommended default for proportions)."""
    if n <= 0:
        return (float("nan"), float("nan"))
    z = _z_alpha(alpha)
    phat = k / n
    z2 = z * z
    denom = 1.0 + z2 / n
    centre = phat + z2 / (2.0 * n)
    half = z * math.sqrt(phat * (1.0 - phat) / n + z2 / (4.0 * n * n))
    lo = (centre - half) / denom
    hi = (centre + half) / denom
    return (max(0.0, lo), min(1.0, hi))


def clopper_pearson_ci(k: int, n: int, alpha: float = DEFAULT_ALPHA) -> tuple[float, float]:
    """Exact Clopper–Pearson CI via binary search on the binomial CDF.

    Conservative: guaranteed coverage >= 1-alpha, often wider than Wilson.
    """
    if n <= 0:
        return (float("nan"), float("nan"))
    if k < 0 or k > n:
        raise ValueError(f"k out of range: {k}/{n}")
    if k == 0:
        lo = 0.0
    else:
        lo = _invert_binom(target=alpha / 2.0, k=k, n=n, side="lower")
    if k == n:
        hi = 1.0
    else:
        hi = _invert_binom(target=alpha / 2.0, k=k, n=n, side="upper")
    return (lo, hi)


def _invert_binom(target: float, k: int, n: int, side: str) -> float:
    """Binary search for Clopper–Pearson bounds.

    lower L: P(X >= k | n, L) = target   (sf increases with p)
    upper U: P(X <= k | n, U) = target   (cdf decreases with p)
    """
    lo, hi = 0.0, 1.0
    for _ in range(100):
        mid = 0.5 * (lo + hi)
        if side == "lower":
            val = binom_sf(k, n, mid)
            if val > target:
                hi = mid  # p too large
            else:
                lo = mid
        else:
            val = binom_cdf(k, n, mid)
            if val > target:
                lo = mid  # p too small (cdf too large)
            else:
                hi = mid
    return 0.5 * (lo + hi)


def _z_alpha(alpha: float) -> float:
    # Approximate N(0,1) quantile via Beasley-Springer/Moro-ish rational for 0.05/0.01.
    # For general alpha use Acklam inverse CDF approximation.
    a = [
        -3.969683028665376e01,
        2.209460984245205e02,
        -2.759285104469687e02,
        1.383577518672690e02,
        -3.066479806614736e01,
        2.506628277459239e00,
    ]
    b = [
        -5.447609879822406e01,
        1.615858368580409e02,
        -1.556989798598866e02,
        6.680131188771972e01,
        -1.328068155288572e01,
    ]
    c = [
        -7.784894002430293e-03,
        -3.223964580411365e-01,
        -2.400758277161838e00,
        -2.549732539343734e00,
        4.374664141464968e00,
        2.938163982698783e00,
    ]
    d = [
        7.784695709041462e-03,
        3.224671290700398e-01,
        2.445134137142996e00,
        3.754408661907416e00,
    ]
    p = 1.0 - alpha / 2.0
    if not 0.0 < p < 1.0:
        raise ValueError(alpha)
    if p < 0.02425:
        q = math.sqrt(-2.0 * math.log(p))
        return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / (
            (((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0
        )
    if p > 1.0 - 0.02425:
        q = math.sqrt(-2.0 * math.log(1.0 - p))
        return -(
            ((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]
        ) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1.0)
    q = p - 0.5
    r = q * q
    return (
        (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
    ) / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1.0)


def bootstrap_proportion_ci(
    successes: int,
    n: int,
    alpha: float = DEFAULT_ALPHA,
    n_boot: int = DEFAULT_BOOT,
    seed: int = SEED,
) -> tuple[float, float]:
    """Percentile bootstrap CI for a Bernoulli proportion (iid draws of size n)."""
    if n <= 0:
        return (float("nan"), float("nan"))
    rng = random.Random(seed)
    # sample with replacement from {1}*k + {0}*(n-k)
    rates = []
    for _ in range(n_boot):
        s = sum(1 for _ in range(n) if rng.randrange(n) < successes)
        rates.append(s / n)
    rates.sort()
    lo_i = int(math.floor(alpha / 2.0 * n_boot))
    hi_i = int(math.ceil((1.0 - alpha / 2.0) * n_boot)) - 1
    lo_i = max(0, min(n_boot - 1, lo_i))
    hi_i = max(0, min(n_boot - 1, hi_i))
    return (rates[lo_i], rates[hi_i])


# ---------------------------------------------------------------------------
# 2x2 tests
# ---------------------------------------------------------------------------

def _log_choose(n: int, k: int) -> float:
    if k < 0 or k > n:
        return float("-inf")
    return math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1)


def fisher_exact_two_sided(a: int, b: int, c: int, d: int) -> float:
    """Two-sided Fisher exact p-value on [[a,b],[c,d]] (success/fail × group)."""
    # a=succ1, b=fail1, c=succ2, d=fail2
    n1 = a + b
    n2 = c + d
    k = a + c
    n = n1 + n2
    if n == 0:
        return 1.0

    def hyper_p(x: int) -> float:
        # P(X=x) for X ~ Hypergeometric
        return math.exp(
            _log_choose(n1, x) + _log_choose(n2, k - x) - _log_choose(n, k)
        )

    lo = max(0, k - n2)
    hi = min(k, n1)
    p_obs = hyper_p(a)
    total = 0.0
    for x in range(lo, hi + 1):
        px = hyper_p(x)
        if px <= p_obs + 1e-12:
            total += px
    return min(1.0, total)


def mcnemar_exact(n01: int, n10: int) -> float:
    """Exact McNemar two-sided p-value on discordant pairs (b=n01, c=n10)."""
    n = n01 + n10
    if n == 0:
        return 1.0
    # under H0, discordants ~ Binomial(n, 0.5); two-sided by doubling smaller tail
    k = min(n01, n10)
    # P(X <= k) * 2, capped at 1; include both extremes when ties
    tail = binom_cdf(k, n, 0.5)
    # if n even and k == n/2, p = 1
    if 2 * k == n:
        return 1.0
    return min(1.0, 2.0 * tail)


def paired_permutation_p(
    diffs: list[float],
    n_perm: int = DEFAULT_PERM,
    seed: int = SEED,
) -> tuple[float, float]:
    """Two-sided paired permutation / sign-flip test on scenario-level diffs.

    Returns (observed_mean_diff, p_value).
    """
    if not diffs:
        return (float("nan"), 1.0)
    obs = sum(diffs) / len(diffs)
    rng = random.Random(seed)
    extreme = 0
    for _ in range(n_perm):
        s = 0.0
        for d in diffs:
            s += d if rng.random() < 0.5 else -d
        mean = s / len(diffs)
        if abs(mean) >= abs(obs) - 1e-15:
            extreme += 1
    return (obs, (extreme + 1) / (n_perm + 1))


# ---------------------------------------------------------------------------
# metric extraction
# ---------------------------------------------------------------------------

@dataclass
class CellCounts:
    k: int
    n: int

    @property
    def rate(self) -> float | None:
        return None if self.n == 0 else self.k / self.n


def count_binary(rows: list[dict], field: str) -> CellCounts:
    known = [r for r in rows if _b(r.get(field)) is not None]
    k = sum(1 for r in known if _b(r.get(field)) is True)
    return CellCounts(k=k, n=len(known))


def filter_rows(
    idx: list[dict],
    *,
    actor: str | None = None,
    profile: str | None = None,
    variant: str | None = None,
    scenario: str | None = None,
    exclude: set[str] | None = None,
) -> list[dict]:
    out = []
    for r in idx:
        if actor is not None and r["actor"] != actor:
            continue
        if profile is not None and r["profile"] != profile:
            continue
        if variant is not None and r["variant"] != variant:
            continue
        if scenario is not None and r["scenario"] != scenario:
            continue
        if _b(r.get("valid")) is not True:
            continue
        if exclude and r["run_id"] in exclude:
            continue
        out.append(r)
    return out


def ci_row(metric: str, cell: CellCounts, alpha: float, n_boot: int, seed: int) -> dict:
    k, n = cell.k, cell.n
    rate = cell.rate
    w_lo, w_hi = wilson_ci(k, n, alpha) if n else (float("nan"), float("nan"))
    c_lo, c_hi = clopper_pearson_ci(k, n, alpha) if n else (float("nan"), float("nan"))
    # bootstrap is unreliable / degenerate for tiny n or 0/n / n/n — still compute
    # but flag in report
    b_lo, b_hi = (
        bootstrap_proportion_ci(k, n, alpha, n_boot, seed) if n else (float("nan"), float("nan"))
    )
    return {
        "metric": metric,
        "k": k,
        "n": n,
        "rate": _f4(rate),
        "wilson_lo": _f4(w_lo),
        "wilson_hi": _f4(w_hi),
        "clopper_lo": _f4(c_lo),
        "clopper_hi": _f4(c_hi),
        "bootstrap_lo": _f4(b_lo),
        "bootstrap_hi": _f4(b_hi),
        "preferred_ci": preferred_ci_label(n, k),
        "ci_note": ci_note(n, k),
    }


def preferred_ci_label(n: int, k: int) -> str:
    if n <= 0:
        return "none"
    if n < 20 or k in (0, n):
        return "clopper_pearson"
    return "wilson"


def ci_note(n: int, k: int) -> str:
    if n <= 0:
        return "empty_denominator"
    if n < 10:
        return "tiny_n_use_exact_binomial_not_bootstrap"
    if k in (0, n):
        return "boundary_rate_bootstrap_degenerates_prefer_wilson_or_cp"
    if n < 30:
        return "small_n_wilson_ok_bootstrap_noisy"
    return "wilson_default_bootstrap_optional"


# ---------------------------------------------------------------------------
# report
# ---------------------------------------------------------------------------

REPORT_MD = """# Стат. интервалы и контрасты (HiveTrace B01–B20)

Скрипт: `audit/stats_intervals.py`.  
Данные: `audit/index.tsv`, исключения hard-failure: **{exclude_src}** (n_exclude={n_exclude}).  
Уровень: **{ci_level:.0%}** CI (alpha={alpha}), bootstrap B={n_boot}, paired permutation R={n_perm}, seed={seed}.  
Знаменатель по умолчанию: **scope B** (hard failures excluded, when matched to current index).

## Что считать primary

| Вопрос | Лучший метод | Почему |
|---|---|---|
| Насколько уверен pooled ASR/FPR (actor×profile, n≈70–100) | **Wilson CI** | покрытие близко к номиналу; не раздувает интервал как Clopper–Pearson; устойчив у краёв лучше Wald |
| ASR на одном сценарии (n=5) | **Clopper–Pearson** (или Wilson) | exact/консервативный биномиальный CI; bootstrap на 0/5 и 5/5 вырождается |
| Снижает ли профиль ASR относительно другого | **paired permutation по сценариям** (+ эффект ΔASR) | одни и те же 20 сценариев → не i.i.d. две группы; перестановка знака diff внутри сценария уважает блокировку |
| Грубый unpaired sanity-check | Fisher exact на 2×2 (succ/fail × profile) | просто, но **игнорирует** парность сценариев → обычно антиконсервативен или не про тот estimand |
| «Хотя бы одна утечка из 5» на сценарии | McNemar exact по scenario-level any-success | чувствительность к определению бинаризации; полезен как secondary |

Bootstrap percentile на pooled доле — **допустимый secondary** при n≳30 и 0<k<n, но не лучше Wilson для простой Bernoulli-доли.

## Ограничения и риски

1. **Не i.i.d. по сценариям.** Pooled ASR смешивает 20 разных атак. Wilson/CP/bootstrap по прогонам описывают неопределённость *смеси*, не «типичного сценария». Для генерализации на новые сценарии нужен cluster/scenario bootstrap или GLMM `(1|scenario)`.
2. **n=5 на клетку сценария.** Мощности мало; CI широкие; «не значимо» ≠ «нет эффекта».
3. **Hard failures.** Без очистки OpenCode/strict раньше занижал ASR (SECURE из-за credits). Текущий exclude: {n_exclude} run_id (источник: {exclude_src}). Если таблица Task 1 устарела относительно `index.tsv`, перезапустите `task1_final.py` или вызовите скрипт с `--scan-failures`.
4. **Cursor FPR=0.** В аудите это артефакт отсутствия permission-телеметрии, не доказательство нулевого FPR — CI тут формально узкие/нулевые, содержательно не интерпретировать.
5. **TCR.** Считается только по прогонам с известным `utility_success`; у Cursor знаменатель сильно меньше 100.
6. **Множественные сравнения.** Три профиля × два актора × несколько метрик — без Holm/BH растёт FWER. Заранее фиксируйте 1–2 primary contrasts (скрипт считает все пары, но в тексте публикации выберите primary).
7. **Fisher unpaired** не заменяет paired permutation: одни сценарии входят в обе группы.
8. **Bootstrap риски:** зависимость от seed при малом B; при k∈{{0,n}} ресэмплы все одинаковы → CI нулевой ширины (обманчивая «уверенность»).
9. **Clopper–Pearson** гарантирует coverage ≥ 1−α, но часто шире необходимого (консервативен) — для pooled n≈100 почти совпадает с Wilson; для n=5 разница заметнее в сторону осторожности.
10. **Атрибуция `stopped_by`** аудитом признана непубликуемой — этот скрипт её не тестирует.

## Как читать артефакты

- `stats_intervals_pooled.tsv` — колонка `preferred_ci` указывает рекомендуемый интервал для строки.
- `stats_intervals_by_scenario.tsv` — scenario-level ASR; смотрите Clopper при n≤5.
- `stats_intervals_contrasts.tsv` — `perm_p` = paired permutation; `fisher_p` = unpaired; `mcnemar_p` = any-success pairing.
- Значимость без величины эффекта недостаточна: смотрите `delta_asr` и CI на долях в pooled-таблице.

## Команда

```bash
python3 audit/stats_intervals.py
python3 audit/stats_intervals.py --include-failures   # scope A (как в TSV)
python3 audit/stats_intervals.py --alpha 0.01 --boot 10000
```
"""


def write_tsv(path: Path, rows: list[dict], fieldnames: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)


def scenario_asr_map(
    idx: list[dict], actor: str, profile: str, exclude: set[str]
) -> dict[str, CellCounts]:
    rows = filter_rows(idx, actor=actor, profile=profile, variant="malicious", exclude=exclude)
    by: dict[str, list[dict]] = defaultdict(list)
    for r in rows:
        by[r["scenario"]].append(r)
    return {sc: count_binary(rs, "attack_success") for sc, rs in sorted(by.items())}


def build_contrasts(
    idx: list[dict],
    exclude: set[str],
    n_perm: int,
    seed: int,
) -> list[dict]:
    out = []
    for actor in ACTORS:
        for p1, p2 in PRIMARY_CONTRASTS:
            m1 = scenario_asr_map(idx, actor, p1, exclude)
            m2 = scenario_asr_map(idx, actor, p2, exclude)
            scenarios = sorted(set(m1) & set(m2))
            # keep scenarios with at least 1 valid trial on both sides
            scenarios = [s for s in scenarios if m1[s].n > 0 and m2[s].n > 0]
            diffs = []
            any_b = any_c = 0  # McNemar: n01 / n10 on any-success
            # also pooled counts for Fisher
            k1 = n1 = k2 = n2 = 0
            for sc in scenarios:
                a, b = m1[sc], m2[sc]
                r1 = a.k / a.n
                r2 = b.k / b.n
                diffs.append(r1 - r2)
                s1 = a.k > 0
                s2 = b.k > 0
                if (not s1) and s2:
                    any_b += 1  # 0→1
                if s1 and (not s2):
                    any_c += 1  # 1→0
                k1 += a.k
                n1 += a.n
                k2 += b.k
                n2 += b.n
            mean_diff, perm_p = paired_permutation_p(diffs, n_perm=n_perm, seed=seed)
            fisher_p = fisher_exact_two_sided(k1, n1 - k1, k2, n2 - k2)
            mcn_p = mcnemar_exact(any_b, any_c)
            out.append(
                {
                    "actor": actor,
                    "profile_a": p1,
                    "profile_b": p2,
                    "n_scenarios": len(scenarios),
                    "asr_a": _f4(k1 / n1 if n1 else None),
                    "asr_b": _f4(k2 / n2 if n2 else None),
                    "k_a": k1,
                    "n_a": n1,
                    "k_b": k2,
                    "n_b": n2,
                    "delta_asr_pooled": _f4((k1 / n1 - k2 / n2) if n1 and n2 else None),
                    "delta_asr_scenario_mean": _f4(mean_diff),
                    "perm_p": _f4(perm_p),
                    "fisher_p": _f4(fisher_p),
                    "mcnemar_any_success_n01": any_b,
                    "mcnemar_any_success_n10": any_c,
                    "mcnemar_p": _f4(mcn_p),
                    "preferred_test": "paired_permutation_scenario_asr",
                    "test_note": (
                        "perm_p respects scenario blocking; "
                        "fisher_p treats trials as unpaired; "
                        "mcnemar uses scenario any-success binary"
                    ),
                }
            )
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repo", type=Path, default=REPO)
    ap.add_argument("--alpha", type=float, default=DEFAULT_ALPHA)
    ap.add_argument("--boot", type=int, default=DEFAULT_BOOT)
    ap.add_argument("--perm", type=int, default=DEFAULT_PERM)
    ap.add_argument("--seed", type=int, default=SEED)
    ap.add_argument(
        "--include-failures",
        action="store_true",
        help="scope A: do not drop hard-failure run_ids",
    )
    ap.add_argument(
        "--scan-failures",
        action="store_true",
        help="re-detect hard failures from agent logs (same signatures as task1_final.py)",
    )
    args = ap.parse_args()

    audit = args.repo / "audit"
    idx = load_index(audit / "index.tsv")
    index_ids = {r["run_id"] for r in idx}
    exclude_all, exclude_src = load_exclude_ids(audit, index_ids)
    if args.scan_failures:
        scanned = scan_hard_failures(args.repo / "logs", idx)
        exclude_all |= scanned
        exclude_src = f"{exclude_src}+scan_logs({len(scanned)})"
    exclude = set() if args.include_failures else exclude_all
    scope = "A_include_failures" if args.include_failures else "B_exclude_hard_failures"

    pooled_rows: list[dict] = []
    for actor in ACTORS:
        for prof in PROFILES:
            mal = filter_rows(
                idx, actor=actor, profile=prof, variant="malicious", exclude=exclude
            )
            ben = filter_rows(
                idx, actor=actor, profile=prof, variant="benign", exclude=exclude
            )
            specs = [
                ("ASR", count_binary(mal, "attack_success")),
                ("IRR", CellCounts(
                    k=sum(1 for r in mal if _b(r.get("attack_success")) is False),
                    n=sum(1 for r in mal if _b(r.get("attack_success")) is not None),
                )),
                ("FPR", count_binary(ben, "defense_false_positive")),
                ("TCR_malicious", count_binary(mal, "utility_success")),
                ("TCR_benign", count_binary(ben, "utility_success")),
            ]
            for metric, cell in specs:
                row = {
                    "scope": scope,
                    "actor": actor,
                    "profile": prof,
                    **ci_row(metric, cell, args.alpha, args.boot, args.seed),
                }
                pooled_rows.append(row)

    scen_rows: list[dict] = []
    for actor in ACTORS:
        for prof in PROFILES:
            mal = filter_rows(
                idx, actor=actor, profile=prof, variant="malicious", exclude=exclude
            )
            by: dict[str, list[dict]] = defaultdict(list)
            for r in mal:
                by[r["scenario"]].append(r)
            for sc, rs in sorted(by.items()):
                cell = count_binary(rs, "attack_success")
                scen_rows.append(
                    {
                        "scope": scope,
                        "actor": actor,
                        "profile": prof,
                        "scenario": sc,
                        **ci_row("ASR", cell, args.alpha, args.boot, args.seed),
                    }
                )

    contrasts = build_contrasts(idx, exclude, args.perm, args.seed)
    for r in contrasts:
        r["scope"] = scope

    write_tsv(
        audit / "stats_intervals_pooled.tsv",
        pooled_rows,
        [
            "scope",
            "actor",
            "profile",
            "metric",
            "k",
            "n",
            "rate",
            "wilson_lo",
            "wilson_hi",
            "clopper_lo",
            "clopper_hi",
            "bootstrap_lo",
            "bootstrap_hi",
            "preferred_ci",
            "ci_note",
        ],
    )
    write_tsv(
        audit / "stats_intervals_by_scenario.tsv",
        scen_rows,
        [
            "scope",
            "actor",
            "profile",
            "scenario",
            "metric",
            "k",
            "n",
            "rate",
            "wilson_lo",
            "wilson_hi",
            "clopper_lo",
            "clopper_hi",
            "bootstrap_lo",
            "bootstrap_hi",
            "preferred_ci",
            "ci_note",
        ],
    )
    write_tsv(
        audit / "stats_intervals_contrasts.tsv",
        contrasts,
        [
            "scope",
            "actor",
            "profile_a",
            "profile_b",
            "n_scenarios",
            "asr_a",
            "asr_b",
            "k_a",
            "n_a",
            "k_b",
            "n_b",
            "delta_asr_pooled",
            "delta_asr_scenario_mean",
            "perm_p",
            "fisher_p",
            "mcnemar_any_success_n01",
            "mcnemar_any_success_n10",
            "mcnemar_p",
            "preferred_test",
            "test_note",
        ],
    )

    report = REPORT_MD.format(
        exclude_src=exclude_src if not args.include_failures else "disabled(--include-failures)",
        n_exclude=len(exclude),
        alpha=args.alpha,
        ci_level=1.0 - args.alpha,
        n_boot=args.boot,
        n_perm=args.perm,
        seed=args.seed,
    )
    # append quick headline table
    lines = [report, "\n## Headline pooled ASR (preferred CI)\n"]
    lines.append(
        "| actor | profile | k/n | rate | preferred | lo | hi |"
    )
    lines.append("|---|---|---|---|---|---|---|")
    for r in pooled_rows:
        if r["metric"] != "ASR":
            continue
        pref = r["preferred_ci"]
        if pref == "wilson":
            lo, hi = r["wilson_lo"], r["wilson_hi"]
        elif pref == "clopper_pearson":
            lo, hi = r["clopper_lo"], r["clopper_hi"]
        else:
            lo = hi = ""
        lines.append(
            f"| {r['actor']} | {r['profile']} | {r['k']}/{r['n']} | {r['rate']} "
            f"| {pref} | {lo} | {hi} |"
        )
    lines.append("\n## Profile contrasts (paired permutation primary)\n")
    lines.append(
        "| actor | a→b | ΔASR pooled | ΔASR scen-mean | perm_p | fisher_p | mcnemar_p |"
    )
    lines.append("|---|---|---|---|---|---|---|")
    for r in contrasts:
        lines.append(
            f"| {r['actor']} | {r['profile_a']}→{r['profile_b']} | "
            f"{r['delta_asr_pooled']} | {r['delta_asr_scenario_mean']} | "
            f"{r['perm_p']} | {r['fisher_p']} | {r['mcnemar_p']} |"
        )
    (audit / "stats_intervals_report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"scope={scope} exclude_src={exclude_src} n_exclude={len(exclude)}")
    print(f"wrote {audit / 'stats_intervals_pooled.tsv'} ({len(pooled_rows)} rows)")
    print(f"wrote {audit / 'stats_intervals_by_scenario.tsv'} ({len(scen_rows)} rows)")
    print(f"wrote {audit / 'stats_intervals_contrasts.tsv'} ({len(contrasts)} rows)")
    print(f"wrote {audit / 'stats_intervals_report.md'}")


if __name__ == "__main__":
    main()
