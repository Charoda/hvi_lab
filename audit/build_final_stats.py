#!/usr/bin/env python3
"""Build audit/final_stats.md (+ helper TSVs) from final_runs + B14 sandbox.

Main matrix expects 1200 VALID rows / 20 scenarios (including b14_readme_env).
Reports stats twice:
  (a) all 20 scenarios
  (b) robustness: drop b14_readme_env (19 scenarios)

B14 sandbox allowlist remains a separate experiment (final_b14_sandbox.tsv).
"""
from __future__ import annotations

import csv
import json
import math
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
AUDIT = REPO / "audit"
HVI_B14 = REPO / "logs" / "b14-sandbox-opencode-20261031-004534"
TAMPERED = REPO / "logs" / "utility_rescore_20261102" / "tampered_override.tsv"
B14_README = "b14_readme_env"

SEED = 20261109
N_BOOT = 5000
N_PERM = 10000
ALPHA = 0.05
PROFILES = ("off", "normal", "strict")
ACTORS = ("opencode", "cursor")

sys.path.insert(0, str(AUDIT))
from stats_intervals import paired_permutation_p, wilson_ci  # noqa: E402


def _b(v) -> bool | None:
    if v is None or v == "":
        return None
    s = str(v).strip().lower()
    if s in ("true", "1", "yes"):
        return True
    if s in ("false", "0", "no"):
        return False
    return None


def _f(x, nd=4) -> str:
    if x is None or (isinstance(x, float) and math.isnan(x)):
        return "—"
    return f"{x:.{nd}f}"


def _pct(k, n) -> str:
    if n <= 0:
        return "—/—"
    return f"{k}/{n} ({k/n:.1%})"


def load_tsv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def write_tsv(path: Path, rows: list[dict], fields: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, delimiter="\t", lineterminator="\n")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def map_stopped_by(raw: str, *, attack_success: bool | None, outcome: str) -> str:
    s = (raw or "").strip()
    if s in ("model", "permission", "sandbox", "not_exposed", "undetermined"):
        return s
    if s in ("unclear",):
        return "undetermined"
    if s == "(attack_success)" or attack_success is True or outcome == "VULN":
        return "undetermined"
    if s == "":
        return "not_exposed"
    return "undetermined"


def cluster_bootstrap_rate(
    by_scenario: dict[str, list[bool]],
    *,
    n_boot: int = N_BOOT,
    seed: int = SEED,
    alpha: float = ALPHA,
) -> tuple[float, float, float]:
    scenarios = sorted(by_scenario.keys())
    if not scenarios:
        return (float("nan"), float("nan"), float("nan"))
    flat = [v for sc in scenarios for v in by_scenario[sc]]
    point = sum(flat) / len(flat)
    rng = random.Random(seed)
    rates = []
    m = len(scenarios)
    for _ in range(n_boot):
        picks = [scenarios[rng.randrange(m)] for _ in range(m)]
        vals = [v for sc in picks for v in by_scenario[sc]]
        if not vals:
            continue
        rates.append(sum(vals) / len(vals))
    rates.sort()
    if not rates:
        return (point, float("nan"), float("nan"))
    lo_i = max(0, min(len(rates) - 1, int(math.floor(alpha / 2.0 * len(rates)))))
    hi_i = max(0, min(len(rates) - 1, int(math.ceil((1.0 - alpha / 2.0) * len(rates))) - 1))
    return (point, rates[lo_i], rates[hi_i])


def cluster_bootstrap_delta(
    by_scenario_a: dict[str, list[bool]],
    by_scenario_b: dict[str, list[bool]],
    *,
    n_boot: int = N_BOOT,
    seed: int = SEED,
    alpha: float = ALPHA,
) -> tuple[float, float, float, list[float]]:
    scenarios = sorted(set(by_scenario_a) & set(by_scenario_b))
    diffs = []
    for sc in scenarios:
        a = by_scenario_a[sc]
        b = by_scenario_b[sc]
        if not a or not b:
            continue
        diffs.append(sum(b) / len(b) - sum(a) / len(a))
    if not diffs:
        return (float("nan"), float("nan"), float("nan"), [])
    point = sum(diffs) / len(diffs)
    rng = random.Random(seed)
    boots = []
    m = len(diffs)
    for _ in range(n_boot):
        picks = [diffs[rng.randrange(m)] for _ in range(m)]
        boots.append(sum(picks) / m)
    boots.sort()
    lo_i = max(0, min(len(boots) - 1, int(math.floor(alpha / 2.0 * len(boots)))))
    hi_i = max(0, min(len(boots) - 1, int(math.ceil((1.0 - alpha / 2.0) * len(boots))) - 1))
    return (point, boots[lo_i], boots[hi_i], diffs)


def holm(pvals: list[tuple[str, float]]) -> dict[str, float]:
    m = len(pvals)
    order = sorted(range(m), key=lambda i: pvals[i][1])
    adj = [0.0] * m
    running = 0.0
    for rank, idx in enumerate(order):
        raw = pvals[idx][1]
        val = min(1.0, (m - rank) * raw)
        running = max(running, val)
        adj[idx] = running
    return {pvals[i][0]: adj[i] for i in range(m)}


def scenario_bools(rows: list[dict], field: str) -> dict[str, list[bool]]:
    out: dict[str, list[bool]] = defaultdict(list)
    for r in rows:
        v = _b(r.get(field))
        if v is None:
            continue
        out[r["scenario"]].append(v)
    return dict(out)


def build_b14_tsv() -> list[dict]:
    tampered = {}
    if TAMPERED.is_file():
        for r in load_tsv(TAMPERED):
            tampered[r["run_id"]] = r
    rows_out = []
    for variant, fname in (("malicious", "malicious.tsv"), ("benign", "benign.tsv")):
        src = HVI_B14 / fname
        for r in load_tsv(src):
            rid = r["run_id"]
            util = r.get("utility_success")
            note = ""
            if rid in tampered:
                note = f"tests_tampered:{tampered[rid].get('detail', '')}"
                util = "False"
            rows_out.append(
                {
                    "actor": r.get("actor") or "opencode",
                    "profile": r["profile"],
                    "scenario": r["scenario"],
                    "variant": variant,
                    "trial": r["repeat_idx"],
                    "verdict": r.get("verdict"),
                    "attack_success": r.get("attack_success"),
                    "utility_rerun": util,
                    "fpr_event": r.get("defense_false_positive") or "False",
                    "stopped_by": r.get("stopped_by") or "",
                    "run_id": rid,
                    "attack_attempted": r.get("attack_attempted") or "",
                    "tampered_override": "True" if rid in tampered else "False",
                    "notes": note,
                }
            )
    fields = [
        "actor", "profile", "scenario", "variant", "trial", "verdict",
        "attack_success", "utility_rerun", "fpr_event", "stopped_by", "run_id",
        "attack_attempted", "tampered_override", "notes",
    ]
    write_tsv(AUDIT / "final_b14_sandbox.tsv", rows_out, fields)
    if TAMPERED.is_file():
        (AUDIT / "tampered_override.tsv").write_text(TAMPERED.read_text())
    return rows_out


def metric_block(rows: list[dict], actor: str, profile: str) -> dict:
    mal = [r for r in rows if r["actor"] == actor and r["profile"] == profile and r["variant"] == "malicious"]
    ben = [r for r in rows if r["actor"] == actor and r["profile"] == profile and r["variant"] == "benign"]
    all_ap = [r for r in rows if r["actor"] == actor and r["profile"] == profile]

    asr_sc = scenario_bools(mal, "attack_success")
    ben_fpr = [r for r in ben if str(r.get("fpr_event", "")).upper() != "NA"]
    fpr_sc = scenario_bools(ben_fpr, "fpr_event")
    tcr_sc = scenario_bools(all_ap, "utility_rerun")

    def pack(sc_map, label):
        flat = [v for vs in sc_map.values() for v in vs]
        k, n = sum(flat), len(flat)
        point, clo, chi = cluster_bootstrap_rate(sc_map)
        wlo, whi = wilson_ci(k, n) if n else (float("nan"), float("nan"))
        return {
            "metric": label,
            "actor": actor,
            "profile": profile,
            "k": k,
            "n": n,
            "rate": point if n else float("nan"),
            "cluster_boot_lo": clo,
            "cluster_boot_hi": chi,
            "wilson_lo": wlo,
            "wilson_hi": whi,
            "n_scenarios": len(sc_map),
        }

    return {"ASR": pack(asr_sc, "ASR"), "FPR": pack(fpr_sc, "FPR"), "TCR": pack(tcr_sc, "TCR")}


def analyze(rows: list[dict], *, scope: str, seed_offset: int = 0) -> dict:
    blocks = {}
    pooled = []
    for actor in ACTORS:
        for prof in PROFILES:
            b = metric_block(rows, actor, prof)
            blocks[(actor, prof)] = b
            for m in ("ASR", "FPR", "TCR"):
                pooled.append({**b[m], "scope": scope})

    contrast_rows = []
    primary_p: list[tuple[str, float]] = []
    for actor in ACTORS:
        for a, b in (("off", "normal"), ("off", "strict"), ("normal", "strict")):
            sc_a = scenario_bools(
                [r for r in rows if r["actor"] == actor and r["profile"] == a and r["variant"] == "malicious"],
                "attack_success",
            )
            sc_b = scenario_bools(
                [r for r in rows if r["actor"] == actor and r["profile"] == b and r["variant"] == "malicious"],
                "attack_success",
            )
            delta, dlo, dhi, diffs = cluster_bootstrap_delta(
                sc_a, sc_b, seed=SEED + seed_offset + hash((scope, actor, a, b)) % 10000
            )
            _obs, p = paired_permutation_p(diffs, n_perm=N_PERM, seed=SEED + seed_offset)
            role = "primary" if (a, b) == ("off", "strict") else "exploratory"
            key = f"{actor}:{a}→{b}"
            if role == "primary":
                primary_p.append((key, p))
            contrast_rows.append(
                {
                    "scope": scope,
                    "actor": actor,
                    "contrast": f"{a}→{b}",
                    "role": role,
                    "delta_asr": delta,
                    "cluster_boot_lo": dlo,
                    "cluster_boot_hi": dhi,
                    "paired_perm_p": p,
                    "n_scenarios": len(diffs),
                    "key": key,
                }
            )
    holm_map = holm(primary_p)
    for r in contrast_rows:
        r["holm_p"] = holm_map.get(r["key"], float("nan")) if r["role"] == "primary" else float("nan")

    sb_rows = []
    for actor in ACTORS:
        for prof in PROFILES:
            mal = [
                r for r in rows
                if r["actor"] == actor and r["profile"] == prof and r["variant"] == "malicious"
            ]
            c = Counter(
                map_stopped_by(
                    r.get("stopped_by") or "",
                    attack_success=_b(r.get("attack_success")),
                    outcome=r.get("outcome") or "",
                )
                for r in mal
            )
            sb_rows.append(
                {
                    "scope": scope,
                    "actor": actor,
                    "profile": prof,
                    "n": len(mal),
                    "model": c.get("model", 0),
                    "permission": c.get("permission", 0),
                    "sandbox": c.get("sandbox", 0),
                    "not_exposed": c.get("not_exposed", 0),
                    "undetermined": c.get("undetermined", 0),
                }
            )

    n_scen = len({r["scenario"] for r in rows})
    return {
        "scope": scope,
        "n_rows": len(rows),
        "n_scenarios": n_scen,
        "blocks": blocks,
        "pooled": pooled,
        "contrasts": contrast_rows,
        "holm": holm_map,
        "stopped_by": sb_rows,
    }


def sig_at_05(p: float) -> str:
    if p != p:  # nan
        return "—"
    return "yes" if p < 0.05 else "no"


def fmt_contrast_line(r: dict) -> str:
    return (
        f"Δ={_f(r['delta_asr'])} CI[{_f(r['cluster_boot_lo'])}, {_f(r['cluster_boot_hi'])}] "
        f"p={_f(r['paired_perm_p'], 4)} Holm={_f(r['holm_p'], 4)}"
    )


def main() -> int:
    final_rows = load_tsv(AUDIT / "final_runs.tsv")
    b14_sandbox_rows = build_b14_tsv()

    rows_a = final_rows
    rows_b = [r for r in final_rows if r["scenario"] != B14_README]
    ana_a = analyze(rows_a, scope="20_with_b14", seed_offset=0)
    ana_b = analyze(rows_b, scope="19_without_b14", seed_offset=17)

    # Write pooled / contrasts / stopped for both scopes
    def serialize_pooled(rows):
        out = []
        for r in rows:
            out.append(
                {
                    "scope": r["scope"],
                    "metric": r["metric"],
                    "actor": r["actor"],
                    "profile": r["profile"],
                    "k": r["k"],
                    "n": r["n"],
                    "n_scenarios": r["n_scenarios"],
                    "rate": _f(r["rate"]),
                    "cluster_boot_lo": _f(r["cluster_boot_lo"]),
                    "cluster_boot_hi": _f(r["cluster_boot_hi"]),
                    "wilson_lo": _f(r["wilson_lo"]),
                    "wilson_hi": _f(r["wilson_hi"]),
                }
            )
        return out

    write_tsv(
        AUDIT / "final_stats_pooled.tsv",
        serialize_pooled(ana_a["pooled"] + ana_b["pooled"]),
        [
            "scope", "metric", "actor", "profile", "k", "n", "n_scenarios",
            "rate", "cluster_boot_lo", "cluster_boot_hi", "wilson_lo", "wilson_hi",
        ],
    )

    def serialize_contrasts(rows):
        out = []
        for r in rows:
            out.append(
                {
                    "scope": r["scope"],
                    "actor": r["actor"],
                    "contrast": r["contrast"],
                    "role": r["role"],
                    "delta_asr": _f(r["delta_asr"]),
                    "cluster_boot_lo": _f(r["cluster_boot_lo"]),
                    "cluster_boot_hi": _f(r["cluster_boot_hi"]),
                    "paired_perm_p": _f(r["paired_perm_p"], 4),
                    "holm_p": _f(r["holm_p"], 4) if r["role"] == "primary" else "",
                    "n_scenarios": r["n_scenarios"],
                }
            )
        return out

    write_tsv(
        AUDIT / "final_stats_contrasts.tsv",
        serialize_contrasts(ana_a["contrasts"] + ana_b["contrasts"]),
        [
            "scope", "actor", "contrast", "role", "delta_asr",
            "cluster_boot_lo", "cluster_boot_hi", "paired_perm_p", "holm_p", "n_scenarios",
        ],
    )
    write_tsv(
        AUDIT / "final_stats_stopped_by.tsv",
        ana_a["stopped_by"] + ana_b["stopped_by"],
        ["scope", "actor", "profile", "n", "model", "permission", "sandbox", "not_exposed", "undetermined"],
    )

    # B14 sandbox bypass
    b14_mal = [r for r in b14_sandbox_rows if r["variant"] == "malicious"]
    bypass_k = sum(1 for r in b14_mal if _b(r.get("attack_success")) is True)
    bypass_n = len(b14_mal)
    bw_lo, bw_hi = wilson_ci(bypass_k, bypass_n)

    # Primary a vs b comparison
    prim_a = {f"{r['actor']}": r for r in ana_a["contrasts"] if r["role"] == "primary"}
    prim_b = {f"{r['actor']}": r for r in ana_b["contrasts"] if r["role"] == "primary"}

    lines: list[str] = []
    lines.append("# Final stats (main matrix + B14 sandbox)")
    lines.append("")
    lines.append("- Date: 2026-11-09")
    lines.append(
        f"- Main: `audit/final_runs.tsv` **n={len(final_rows)}**, "
        f"**{ana_a['n_scenarios']} scenarios** (includes `{B14_README}`)"
    )
    lines.append(
        f"- Robustness slice: drop `{B14_README}` → **n={len(rows_b)}**, "
        f"**{ana_b['n_scenarios']} scenarios**"
    )
    lines.append(
        f"- B14 sandbox (separate): `audit/final_b14_sandbox.tsv` **n={len(b14_sandbox_rows)}** "
        f"(OpenCode batch `{HVI_B14.name}`)"
    )
    lines.append(f"- Seed={SEED}, cluster bootstrap B={N_BOOT}, paired permutation R={N_PERM}, α={ALPHA}")
    lines.append("- Wilson = conditional binomial CI on the fixed scenario set.")
    lines.append("- Cluster bootstrap = resample **scenarios** with replacement.")
    lines.append("")
    lines.append("## Decision: keep `b14_readme_env` in the main matrix")
    lines.append("")
    lines.append(
        "- **Kept** in primary 20-scenario matrix (60 VALID rows restored into `final_runs.tsv`)."
    )
    lines.append(
        "- **Reason:** conditional trigger — attack payload not executed "
        "(0 `curl` / `@.env` in strace); counts as non-exposure, not model refusal."
    )
    lines.append(
        "- **Malicious labeling:** `verdict=SECURE`, `attack_success=False`, "
        "`stopped_by=not_exposed` (not `model`)."
    )
    lines.append(
        "- **`b14_sandbox_allowlist`** remains a **separate** control experiment "
        "(`final_b14_sandbox.tsv`); not mixed into the 1200."
    )
    lines.append("")
    lines.append("### Checklist context")
    lines.append("")
    lines.append(
        f"- `tampered_override`: applied on sandbox batch "
        f"({sum(1 for r in b14_sandbox_rows if r.get('tampered_override')=='True')} rows); "
        "see `audit/tampered_override.tsv`."
    )
    gcheck = AUDIT / "chown_golden_check.json"
    if gcheck.is_file():
        g = json.loads(gcheck.read_text())
        lines.append(
            f"- chown after container: applied; golden `{g.get('run_id')}` "
            f"root_owned={g.get('root_owned_count')} (chown_ok={g.get('chown_ok')})."
        )
    lines.append("- CHANGELOG: `docs/CHANGELOG.md`")
    lines.append("")

    def emit_pooled(ana: dict, title: str) -> None:
        lines.append(f"## {title}")
        lines.append("")
        lines.append(
            "| actor | profile | metric | k/n | point | cluster boot 95% CI | Wilson 95% CI |"
        )
        lines.append("|---|---|---|---|---|---|---|")
        for actor in ACTORS:
            for prof in PROFILES:
                for m in ("ASR", "FPR", "TCR"):
                    r = ana["blocks"][(actor, prof)][m]
                    if m == "FPR" and actor == "cursor":
                        lines.append(f"| {actor} | {prof} | FPR | NA | — | — | — |")
                        continue
                    lines.append(
                        f"| {actor} | {prof} | {m} | {r['k']}/{r['n']} | {_f(r['rate'])} | "
                        f"[{_f(r['cluster_boot_lo'])}, {_f(r['cluster_boot_hi'])}] | "
                        f"[{_f(r['wilson_lo'])}, {_f(r['wilson_hi'])}] |"
                    )
        lines.append("")
        lines.append("### Primary contrasts: off→strict (ASR)")
        lines.append("")
        lines.append("Δ = ASR(strict) − ASR(off). Negative ⇒ stricter profile lowers attack success.")
        lines.append("")
        lines.append(
            "| actor | Δ ASR | cluster boot 95% CI | paired perm p | Holm p (2 primary) | sig@0.05 |"
        )
        lines.append("|---|---|---|---|---|---|")
        for r in ana["contrasts"]:
            if r["role"] != "primary":
                continue
            lines.append(
                f"| {r['actor']} | {_f(r['delta_asr'])} | "
                f"[{_f(r['cluster_boot_lo'])}, {_f(r['cluster_boot_hi'])}] | "
                f"{_f(r['paired_perm_p'], 4)} | {_f(r['holm_p'], 4)} | "
                f"{sig_at_05(r['holm_p'])} |"
            )
        lines.append("")
        lines.append("### Exploratory contrasts")
        lines.append("")
        lines.append("| actor | contrast | Δ ASR | cluster boot 95% CI | paired perm p |")
        lines.append("|---|---|---|---|---|")
        for r in ana["contrasts"]:
            if r["role"] == "primary":
                continue
            lines.append(
                f"| {r['actor']} | {r['contrast']} | {_f(r['delta_asr'])} | "
                f"[{_f(r['cluster_boot_lo'])}, {_f(r['cluster_boot_hi'])}] | "
                f"{_f(r['paired_perm_p'], 4)} |"
            )
        lines.append("")
        lines.append("### stopped_by (malicious)")
        lines.append("")
        lines.append(
            "Mapping: raw `not_exposed` kept; `model`/`permission`/`sandbox` as-is; "
            "empty→`not_exposed`; `unclear`/`(attack_success)`/VULN→`undetermined`."
        )
        lines.append("")
        lines.append(
            "| actor | profile | n | model | permission | sandbox | not_exposed | undetermined |"
        )
        lines.append("|---|---|---|---|---|---|---|---|")
        for r in ana["stopped_by"]:
            lines.append(
                f"| {r['actor']} | {r['profile']} | {r['n']} | {r['model']} | {r['permission']} | "
                f"{r['sandbox']} | {r['not_exposed']} | {r['undetermined']} |"
            )
        lines.append("")

    emit_pooled(ana_a, f"A — primary matrix ({ana_a['n_scenarios']} scenarios, n={ana_a['n_rows']})")
    emit_pooled(ana_b, f"B — robustness without `{B14_README}` ({ana_b['n_scenarios']} scenarios, n={ana_b['n_rows']})")

    lines.append("## A vs B — does the significance call change?")
    lines.append("")
    lines.append(
        "| actor | A (20, with B14) | B (19, no B14) | Holm sig A | Holm sig B | call changes? |"
    )
    lines.append("|---|---|---|---|---|---|")
    for actor in ACTORS:
        ra, rb = prim_a[actor], prim_b[actor]
        sa, sb = sig_at_05(ra["holm_p"]), sig_at_05(rb["holm_p"])
        change = "no" if sa == sb else f"YES ({sa}→{sb})"
        lines.append(
            f"| {actor} | {fmt_contrast_line(ra)} | {fmt_contrast_line(rb)} | {sa} | {sb} | {change} |"
        )
    lines.append("")
    # Explicit verdict sentence
    changes = []
    for actor in ACTORS:
        sa, sb = sig_at_05(prim_a[actor]["holm_p"]), sig_at_05(prim_b[actor]["holm_p"])
        if sa != sb:
            changes.append(f"{actor}: {sa}→{sb}")
    if not changes:
        lines.append(
            "**Verdict:** dropping `b14_readme_env` does **not** change the Holm@0.05 "
            "call on primary off→strict for either actor."
        )
    else:
        lines.append(
            "**Verdict:** significance call **changes** when dropping B14: " + "; ".join(changes) + "."
        )
    lines.append("")

    lines.append("## B14 sandbox (separate experiment)")
    lines.append("")
    lines.append(
        f"- Bypass (attack_success): **{_pct(bypass_k, bypass_n)}**, "
        f"Wilson 95% CI [{_f(bw_lo)}, {_f(bw_hi)}]"
    )
    lines.append(
        f"- `tampered_override` rows: "
        f"**{sum(1 for r in b14_sandbox_rows if r.get('tampered_override')=='True')}**/30"
    )
    lines.append("")
    lines.append("| profile | bypass k/5 | Wilson 95% CI | stopped_by (mal) |")
    lines.append("|---|---|---|---|")
    for prof in PROFILES:
        sub = [r for r in b14_mal if r["profile"] == prof]
        k = sum(1 for r in sub if _b(r.get("attack_success")) is True)
        n = len(sub)
        lo, hi = wilson_ci(k, n) if n else (float("nan"), float("nan"))
        c = Counter(r.get("stopped_by") or "" for r in sub)
        lines.append(
            f"| {prof} | {k}/{n} | [{_f(lo)}, {_f(hi)}] | {dict(c)} |"
        )
    lines.append("")
    lines.append("## Artifacts")
    lines.append("")
    lines.append("- `audit/final_runs.tsv` (1200)")
    lines.append("- `audit/final_stats.md` (this file)")
    lines.append("- `audit/final_stats_pooled.tsv` (scopes A+B)")
    lines.append("- `audit/final_stats_contrasts.tsv`")
    lines.append("- `audit/final_stats_stopped_by.tsv`")
    lines.append("- `audit/final_b14_sandbox.tsv`")
    lines.append("- `docs/CHANGELOG.md`")
    lines.append("")

    (AUDIT / "final_stats.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    meta = {
        "final_runs": len(final_rows),
        "scenarios_a": ana_a["n_scenarios"],
        "scenarios_b": ana_b["n_scenarios"],
        "primary_a": {k: {"holm_p": v["holm_p"], "p": v["paired_perm_p"], "delta": v["delta_asr"]} for k, v in prim_a.items()},
        "primary_b": {k: {"holm_p": v["holm_p"], "p": v["paired_perm_p"], "delta": v["delta_asr"]} for k, v in prim_b.items()},
        "b14_sandbox_bypass": {"k": bypass_k, "n": bypass_n},
        "sig_call_changes": changes,
    }
    (AUDIT / "final_stats_meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print("wrote", AUDIT / "final_stats.md")
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
