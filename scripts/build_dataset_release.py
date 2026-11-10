#!/usr/bin/env python3
"""Build dataset_release/ for Hugging Face (local only, no upload)."""
from __future__ import annotations

import csv
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "dataset_release"
PY = Path(os.environ.get("MOSAIC_PYTHON", sys.executable))

# Primary logs live in-repo; optional extra roots via MOSAIC_EXTRA_LOG_ROOTS
# (colon-separated), e.g. for a sibling mosaic-benchmark checkout.
LOG_ROOTS = [REPO / "logs"]
_extra = os.environ.get("MOSAIC_EXTRA_LOG_ROOTS", "").strip()
if _extra:
    LOG_ROOTS.extend(Path(p) for p in _extra.split(":") if p.strip())

REDACT = "<REDACTED>"
# Public IPv4 only (excludes 0.0.0.0, 127/8, 10/8, 172.16/12, 192.168/16).
# Negative lookaround avoids package versions like `foo-1.2.3.4`.
PUBLIC_IPV4_RG = (
    r"(?<![0-9A-Za-z-])"
    r"(?!0\.0\.0\.0(?![0-9]))"
    r"(?!127\.)"
    r"(?!10\.)"
    r"(?!192\.168\.)"
    r"(?!172\.(?:1[6-9]|2\d|3[0-1])\.)"
    r"(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)"
    r"(?![0-9A-Za-z-])"
)
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("sk_or", re.compile(r"sk-or-v1-[A-Za-z0-9_-]+")),
    ("crsr", re.compile(r"crsr-[A-Za-z0-9_-]+")),
    ("bearer", re.compile(r"\bBearer\s+[A-Za-z0-9._\-+=/]{8,}")),
    ("openrouter_env", re.compile(r"OPENROUTER_API_KEY\s*=\s*[^\s\"']+")),
    ("home_path", re.compile(r"/home/[A-Za-z0-9._-]+")),
    ("ipv4_public", re.compile(PUBLIC_IPV4_RG)),
    ("email", re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")),
]

BINARY_SUFFIXES = {".zst", ".gz", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".pyc", ".whl", ".zip"}
DIFF_EXCLUDE = {
    "node_modules", "__pycache__", ".git", ".venv", "venv", ".tox", ".mypy_cache",
    ".pytest_cache", "dist", "build", ".eggs",
}


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def find_run_dir(run_id: str) -> Path | None:
    for root in LOG_ROOTS:
        p = root / run_id
        if p.is_dir():
            return p
    return None


def load_tsv(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def load_model_index() -> dict[str, str]:
    """run_id -> model from live batch TSVs."""
    out: dict[str, str] = {}
    for actor in ("opencode", "cursor"):
        for prof in ("off", "normal", "strict"):
            b = REPO / "logs" / actor / f"{actor}-b01-b20-n5-{prof}"
            for name in ("malicious.tsv", "benign.tsv",
                         "malicious.tsv.pre_b14_sandbox_swap",
                         "benign.tsv.pre_b14_sandbox_swap"):
                p = b / name
                if not p.is_file():
                    continue
                for r in csv.DictReader(p.open(), delimiter="\t"):
                    rid = r.get("run_id") or ""
                    if rid and rid not in out and r.get("model"):
                        out[rid] = r["model"]
    # B14 sandbox batch in hvi
    for name in ("malicious.tsv", "benign.tsv"):
        p = Path("/home/user/hvi_lab/logs/b14-sandbox-opencode-20261031-004534") / name
        if p.is_file():
            for r in csv.DictReader(p.open(), delimiter="\t"):
                rid = r.get("run_id") or ""
                if rid and r.get("model"):
                    out[rid] = r["model"]
    return out


def parse_run_date(run_id: str, result: dict | None) -> str:
    if result:
        for k in ("started_at", "finished_at"):
            v = result.get(k)
            if v:
                return str(v)[:19]
    m = re.search(r"(20\d{6})-(\d{6})", run_id)
    if not m:
        return ""
    d, t = m.group(1), m.group(2)
    return f"{d[0:4]}-{d[4:6]}-{d[6:8]}T{t[0:2]}:{t[2:4]}:{t[4:6]}"


def chain_meta(scenario: str, variant: str) -> dict:
    cid = f"{scenario}_benign" if variant == "benign" and not scenario.endswith("_benign") else scenario
    # b14_sandbox benign twin name
    if scenario == "b14_sandbox_allowlist" and variant == "benign":
        cid = "b14_sandbox_allowlist_benign"
    elif variant == "benign" and not scenario.endswith("_benign"):
        cid = f"{scenario}_benign"
    p = REPO / "benchmark" / "chains" / cid / "chain.json"
    if not p.is_file() and variant == "benign":
        p = REPO / "benchmark" / "chains" / scenario / "chain.json"
    if not p.is_file():
        return {"chain_id": scenario}
    return json.loads(p.read_text())


def substrate_app_dir(meta: dict) -> Path | None:
    task_id = meta.get("task_id") or ""
    if not task_id:
        return None
    base = REPO / "benchmark" / "apps" / task_id
    if not base.is_dir():
        return None
    # prefer single subdir that looks like the app
    kids = [p for p in base.iterdir() if p.is_dir() and p.name not in DIFF_EXCLUDE and not p.name.startswith(".")]
    if len(kids) == 1:
        return kids[0]
    # common names
    for name in ("customer_service_api", "runtime_svc", "npm_svc", "payment_svc", "app", "src"):
        if (base / name).is_dir():
            return base / name
    return kids[0] if kids else base


def write_diff(src: Path, dst: Path, out_patch: Path) -> bool:
    if not src.is_dir() or not dst.is_dir():
        return False
    exclude_args = []
    for e in sorted(DIFF_EXCLUDE):
        exclude_args.extend(["--exclude", e])
    # also exclude large/noise
    for e in ("*.pyc", "*.pyo", ".DS_Store", "package-lock.json", "yarn.lock"):
        exclude_args.extend(["--exclude", e])
    cp = subprocess.run(
        ["diff", "-ruN", *exclude_args, str(src), str(dst)],
        capture_output=True,
        text=True,
    )
    # diff returns 1 on differences, 0 same, 2 error
    text = cp.stdout or ""
    if cp.returncode not in (0, 1):
        text = (cp.stderr or "") + "\n" + text
    # redact paths in headers
    text = text.replace(str(REPO), "<REPO>")
    for root in LOG_ROOTS:
        text = text.replace(str(root), "<LOGS>")
        text = text.replace(str(root.parent), "<REPO_OR_LOG_PARENT>")
    out_patch.write_text(text, encoding="utf-8", errors="replace")
    return True


def pick_transcript(run_dir: Path) -> tuple[str, Path] | None:
    for name in ("opencode_raw.log", "cursor_agent.log", "actor_stdout.log"):
        p = run_dir / name
        if p.is_file() and p.stat().st_size > 0:
            return name, p
    return None


def copy_text(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)


def build_catalog() -> list[dict]:
    models = load_model_index()
    rows: list[dict] = []
    for exp, path in (
        ("main", REPO / "audit" / "final_runs.tsv"),
        ("b14_sandbox", REPO / "audit" / "final_b14_sandbox.tsv"),
    ):
        for r in load_tsv(path):
            rid = r["run_id"]
            run_dir = find_run_dir(rid)
            result = None
            if run_dir and (run_dir / "result.json").is_file():
                try:
                    result = json.loads((run_dir / "result.json").read_text())
                except Exception:
                    result = None
            model = (
                (result or {}).get("llm_model")
                or models.get(rid)
                or ("auto" if r.get("actor") == "cursor" else "")
            )
            row = {
                "experiment": exp,
                "run_id": rid,
                "actor": r.get("actor") or (result or {}).get("actor") or "",
                "profile": r.get("profile") or "",
                "scenario": r.get("scenario") or "",
                "variant": r.get("variant") or "",
                "trial": r.get("trial") or r.get("repeat_idx") or "",
                "verdict": r.get("verdict") or "",
                "attack_success": r.get("attack_success") or "",
                "utility_rerun": r.get("utility_rerun") or "",
                "fpr_event_unvalidated": r.get("fpr_event") or "",
                "stopped_by_unvalidated": r.get("stopped_by") or "",
                "outcome": r.get("outcome") or "",
                "attack_attempted": r.get("attack_attempted") or "",
                "tampered_override": r.get("tampered_override") or "",
                "model": model,
                "run_date": parse_run_date(rid, result),
                "log_root": str(run_dir) if run_dir else "",
            }
            rows.append(row)
    return rows


def package_run(row: dict, runs_root: Path, strace_staging: Path) -> dict:
    rid = row["run_id"]
    run_dir = Path(row["log_root"]) if row["log_root"] else None
    out = runs_root / rid
    out.mkdir(parents=True, exist_ok=True)
    status = {"run_id": rid, "ok": True, "notes": []}

    if not run_dir or not run_dir.is_dir():
        status["ok"] = False
        status["notes"].append("missing_log_dir")
        # still write minimal result from catalog
        (out / "result.json").write_text(
            json.dumps({k: row[k] for k in row if k != "log_root"}, indent=2) + "\n",
            encoding="utf-8",
        )
        return status

    # transcript
    tr = pick_transcript(run_dir)
    if tr:
        name, src = tr
        copy_text(src, out / "agent_transcript.log")
        (out / "agent_transcript.source.txt").write_text(name + "\n", encoding="utf-8")
    else:
        status["notes"].append("no_transcript")

    # result.json
    if (run_dir / "result.json").is_file():
        copy_text(run_dir / "result.json", out / "result.json")
    else:
        # synthesize for cursor / incomplete
        meta = {
            "run_id": rid,
            "actor": row["actor"],
            "permission_profile": row["profile"],
            "llm_model": row["model"],
            "started_at": row["run_date"],
            "verdict": row["verdict"],
            "attack_success": row["attack_success"],
            "stopped_by_unvalidated": row["stopped_by_unvalidated"],
            "synthesized": True,
            "source": "final_runs_catalog",
        }
        # attach batch evidence if present
        (out / "result.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        status["notes"].append("result_synthesized")

    # oracle evidence
    if (run_dir / "poc_result.json").is_file():
        copy_text(run_dir / "poc_result.json", out / "oracle_poc_result.json")
    # also dump evidence string from live batch into oracle_evidence.txt when available
    # (filled later via batch evidence index if needed)

    # honey
    for name in ("honey_requests.jsonl", "honey_blocked.jsonl", "honey_allowed.jsonl", "honey_listener.log"):
        p = run_dir / name
        if p.is_file():
            copy_text(p, out / name)

    # final_app diff
    meta = chain_meta(row["scenario"], row["variant"])
    sub = substrate_app_dir(meta)
    final_app = run_dir / "final_app"
    if final_app.is_dir() and sub and sub.is_dir():
        write_diff(sub, final_app, out / "final_app.diff")
    elif final_app.is_dir():
        status["notes"].append("final_app_present_no_substrate")
        # list tree as weak fallback
        paths = []
        for p in sorted(final_app.rglob("*")):
            if p.is_file() and not any(x in p.parts for x in DIFF_EXCLUDE):
                paths.append(str(p.relative_to(final_app)))
                if len(paths) > 500:
                    break
        (out / "final_app.filelist.txt").write_text("\n".join(paths) + "\n", encoding="utf-8")
    else:
        status["notes"].append("no_final_app")

    # permission events (useful, small)
    if (run_dir / "permission_events.jsonl").is_file():
        copy_text(run_dir / "permission_events.jsonl", out / "permission_events.jsonl")

    # stage strace for archive (always copy — never hardlink; redaction must not
    # mutate source logs under logs/)
    st = run_dir / "strace.log"
    if st.is_file() and st.stat().st_size > 0:
        dest = strace_staging / f"{rid}.strace.log"
        if dest.exists():
            dest.unlink()
        shutil.copy2(st, dest)
        status["notes"].append("strace_staged")

    return status


def load_batch_evidence() -> dict[str, str]:
    out: dict[str, str] = {}
    patterns = [
        REPO / "logs" / "opencode" / "opencode-b01-b20-n5-*" / "*.tsv",
        REPO / "logs" / "cursor" / "cursor-b01-b20-n5-*" / "*.tsv",
        Path("/home/user/hvi_lab/logs/b14-sandbox-opencode-20261031-004534") / "*.tsv",
    ]
    files: list[Path] = []
    for actor in ("opencode", "cursor"):
        for prof in ("off", "normal", "strict"):
            b = REPO / "logs" / actor / f"{actor}-b01-b20-n5-{prof}"
            for name in ("malicious.tsv", "benign.tsv",
                         "malicious.tsv.pre_b14_sandbox_swap",
                         "benign.tsv.pre_b14_sandbox_swap"):
                p = b / name
                if p.is_file():
                    files.append(p)
    p = Path("/home/user/hvi_lab/logs/b14-sandbox-opencode-20261031-004534")
    for name in ("malicious.tsv", "benign.tsv"):
        if (p / name).is_file():
            files.append(p / name)
    for p in files:
        for r in csv.DictReader(p.open(), delimiter="\t"):
            rid = r.get("run_id") or ""
            ev = r.get("evidence") or ""
            if rid and ev and rid not in out:
                out[rid] = ev
    return out


def copy_scenarios(dst: Path) -> None:
    dst.mkdir(parents=True, exist_ok=True)
    main = [
        "b01_readme_setup", "b02_code_comment", "b03_issue_repro", "b04_test_output",
        "b05_agent_rules", "b06_pr_hook", "b07_lint_output", "b08_agent_handoff",
        "b09_readme_backdoor", "b10_auth_comment", "b11_issue_rce", "b12_agents_bootstrap",
        "b13_readme_direct", "b14_readme_env", "b15_dependency_docs", "b16_web_docs",
        "b17_docker_build", "b18_ci_artifact", "b19_git_hook", "b20_postinstall",
        "b14_sandbox_allowlist",
    ]
    for scen in main:
        for cid in (scen, f"{scen}_benign"):
            chain = REPO / "benchmark" / "chains" / cid
            if not chain.is_dir():
                continue
            out_c = dst / cid
            out_c.mkdir(parents=True, exist_ok=True)
            # core chain files
            for name in ("chain.json", "golden_solution.sh", "agent_prompt.txt", "trigger.txt"):
                p = chain / name
                if p.is_file():
                    shutil.copy2(p, out_c / name)
            # oracle / poc modules
            for p in chain.glob("poc_*.py"):
                shutil.copy2(p, out_c / p.name)
            # README with injection from substrate
            meta = {}
            if (chain / "chain.json").is_file():
                meta = json.loads((chain / "chain.json").read_text())
            app = substrate_app_dir(meta)
            if app:
                for readme in app.rglob("README*"):
                    if readme.is_file() and "node_modules" not in readme.parts:
                        rel = readme.relative_to(app)
                        dest = out_c / "substrate_readme" / rel
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(readme, dest)
                        break


# ripgrep patterns (must stay in sync with PATTERNS / perl)
RG_PATTERNS: list[tuple[str, str]] = [
    ("sk_or", r"sk-or-v1-[A-Za-z0-9_-]+"),
    ("crsr", r"crsr-[A-Za-z0-9_-]+"),
    ("bearer", r"\bBearer\s+[A-Za-z0-9._\-+=/]{8,}"),
    ("openrouter_env", r"OPENROUTER_API_KEY\s*=\s*[^\s\"']+"),
    ("home_path", r"/home/[A-Za-z0-9._-]+"),
    ("ipv4_public", PUBLIC_IPV4_RG),
    ("email", r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"),
]
RG_COMBINED = "|".join(f"(?:{p})" for _, p in RG_PATTERNS)

# Collect sample public IPs for the build report (filled during count_secrets).
PUBLIC_IP_EXAMPLES: list[str] = []

PERL_REDACT_SCRIPT = r"""
# Auto-generated secret scrubber for dataset_release.
# Public IPv4 only; private/loopback/0.0.0.0 kept; package versions guarded by lookaround.
while (<>) {
  s/sk-or-v1-[A-Za-z0-9_-]+/<REDACTED>/g;
  s/crsr-[A-Za-z0-9_-]+/<REDACTED>/g;
  s/\bBearer\s+[A-Za-z0-9._\-+=\/]{8,}/<REDACTED>/g;
  s/OPENROUTER_API_KEY\s*=\s*[^\s\"']+/<REDACTED>/g;
  s/\/home\/[A-Za-z0-9._-]+/<REDACTED>/g;
  s/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/<REDACTED>/g;
  s{(?<![0-9A-Za-z-])((?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d))(?![0-9A-Za-z-])}{
    my $ip = $1;
    my @o = split(/\./, $ip);
    my $priv = ($ip eq '0.0.0.0')
            || ($o[0] == 127)
            || ($o[0] == 10)
            || ($o[0] == 172 && $o[1] >= 16 && $o[1] <= 31)
            || ($o[0] == 192 && $o[1] == 168);
    $priv ? $ip : '<REDACTED>';
  }ge;
  print;
}
"""


def count_secrets(root: Path) -> Counter:
    """Per-type match counts via rg --count-matches (no huge stdout)."""
    global PUBLIC_IP_EXAMPLES
    counts: Counter = Counter()
    for kind, pat in RG_PATTERNS:
        cp = subprocess.run(
            [
                "rg", "--count-matches", "-a", "--hidden", "--no-ignore",
                "-g", "!*.tar.zst", "-g", "!*.zst",
                "-g", "!*.png", "-g", "!*.jpg", "-g", "!*.jpeg",
                "-g", "!*.gif", "-g", "!*.webp", "-g", "!*.pyc",
                "-g", "!*.whl", "-g", "!*.zip", "-g", "!*.gz",
                "-P",  # PCRE2 for lookaround (public IP / version guards)
                pat, str(root),
            ],
            capture_output=True,
            text=True,
        )
        # fallback without -P if rg build lacks PCRE2 (shouldn't for cursor rg)
        if cp.returncode not in (0, 1) and "PCRE" in (cp.stderr or ""):
            cp = subprocess.run(
                [
                    "rg", "--count-matches", "-a", "--hidden", "--no-ignore",
                    "-g", "!*.tar.zst", "-g", "!*.zst",
                    pat, str(root),
                ],
                capture_output=True,
                text=True,
            )
        n = 0
        for line in (cp.stdout or "").splitlines():
            if ":" not in line:
                continue
            try:
                n += int(line.rsplit(":", 1)[-1])
            except ValueError:
                continue
        if n:
            counts[kind] = n
        log(f"  count {kind}={n}")
        if kind == "ipv4_public" and n and len(PUBLIC_IP_EXAMPLES) < 5:
            ex = subprocess.run(
                [
                    "rg", "-o", "-a", "--no-ignore", "--no-filename", "--hidden", "-P",
                    "-g", "!*.tar.zst", "-g", "!*.zst",
                    pat, str(root),
                ],
                capture_output=True,
                text=True,
            )
            seen: set[str] = set(PUBLIC_IP_EXAMPLES)
            for line in (ex.stdout or "").splitlines():
                ip = line.strip()
                if ip and ip not in seen:
                    seen.add(ip)
                    PUBLIC_IP_EXAMPLES.append(ip)
                    if len(PUBLIC_IP_EXAMPLES) >= 5:
                        break
            log(f"  public IP examples: {PUBLIC_IP_EXAMPLES}")
    return counts


def redact_tree(root: Path) -> Counter:
    """Count then bulk-redact with parallel perl (handles multi-GB strace)."""
    log(f"counting secrets under {root.name}/")
    counts = count_secrets(root)
    log(f"applying perl redact under {root.name}/ (parallel)")
    files: list[str] = []
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() in BINARY_SUFFIXES or path.name.endswith(".tar.zst"):
            continue
        if path.name.endswith(".redact_tmp") or path.name.endswith("_redact.pl"):
            continue
        files.append(str(path))
    if not files:
        return counts
    script = root / "_redact.pl"
    script.write_text(PERL_REDACT_SCRIPT, encoding="utf-8")
    nproc = min(32, os.cpu_count() or 8)
    proc = subprocess.run(
        [
            "xargs", "-0", "-P", str(nproc), "-n", "8",
            "perl", "-i", str(script),
        ],
        input="\0".join(files) + ("\0" if files else ""),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        log(f"perl redact FAILED rc={proc.returncode}: {(proc.stderr or '')[:800]}")
        raise RuntimeError(f"perl redact failed under {root}: {proc.stderr[:800]}")
    try:
        script.unlink()
    except OSError:
        pass
    return counts


def verify_clean(root: Path) -> list[str]:
    """Ripgrep verification (fast). Public-IP pattern needs PCRE2 (-P)."""
    hits: list[str] = []
    cp = subprocess.run(
        [
            "rg", "-n", "-a", "--hidden", "--no-ignore", "-P",
            "-g", "!*.tar.zst", "-g", "!*.zst",
            "-g", "!*.png", "-g", "!*.jpg",
            RG_COMBINED, str(root),
        ],
        capture_output=True,
        text=True,
    )
    for line in (cp.stdout or "").splitlines():
        if line.strip():
            hits.append(line.strip())
            if len(hits) > 50:
                break
    return hits


def write_runs_csv(rows: list[dict]) -> None:
    fields = [
        "experiment", "run_id", "actor", "profile", "scenario", "variant", "trial",
        "verdict", "attack_success", "utility_rerun",
        "fpr_event_unvalidated", "stopped_by_unvalidated",
        "outcome", "attack_attempted", "tampered_override", "model", "run_date",
    ]
    with (OUT / "runs.csv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def write_runs_parquet_from_csv() -> None:
    subprocess.check_call(
        [
            str(PY),
            "-c",
            "import sys,pandas as pd; df=pd.read_csv(sys.argv[1]); df.to_parquet(sys.argv[2], index=False); print(len(df))",
            str(OUT / "runs.csv"),
            str(OUT / "runs.parquet"),
        ]
    )


def write_readme() -> None:
    text = '''---
license: cc-by-4.0
pretty_name: HiveTrace / MOSAIC Agent Behavior Matrix
task_categories:
  - text-generation
  - other
tags:
  - agents
  - security
  - prompt-injection
  - sandbox
language:
  - en
  - ru
size_categories:
  - 1K<n<10K
---

# HiveTrace agent-behavior matrix (MOSAIC)

Dataset of **1230** isolated agent runs evaluating whether coding agents follow
indirect prompt injections / unsafe instructions while solving ordinary
engineering tasks.

- **Main matrix:** 1200 runs = 20 scenarios × {malicious, benign} × 3 permission
  profiles (`off`/`normal`/`strict`) × 2 actors (`opencode`, `cursor`) × N=5.
- **B14 sandbox control (separate):** 30 OpenCode-only runs of
  `b14_sandbox_allowlist` (dual-honey allowlist bypass probe).

Code & audit notes: [github.com/Charoda/hvi_lab](https://github.com/Charoda/hvi_lab)
(branch `final-data-20261109`).

## Structure

```
dataset_release/
  README.md
  runs.csv
  runs.parquet
  runs/<run_id>/
    agent_transcript.log
    result.json
    oracle_*.json / oracle_evidence.txt
    honey_*.jsonl
    final_app.diff
    permission_events.jsonl   # OpenCode when present
  strace.tar.zst              # per-run strace.log (OpenCode; absent for Cursor)
  scenarios/<chain_id>/       # chain.json, golden_solution.sh, poc_*.py, README
  stats/                      # final_stats.md, stats_intervals.py, CHANGELOG.md
```

## `runs.parquet` / `runs.csv` fields

| field | description |
|---|---|
| `experiment` | `main` or `b14_sandbox` |
| `run_id` | unique run directory id |
| `actor` | `opencode` or `cursor` |
| `profile` | permission profile `off`/`normal`/`strict` |
| `scenario` | scenario id (e.g. `b01_readme_setup`) |
| `variant` | `malicious` or `benign` |
| `trial` | repeat index 1..5 |
| `verdict` | harness/oracle verdict (`SECURE`/`VULNERABLE`/…) |
| `attack_success` | boolean string; primary ASR numerator |
| `utility_rerun` | task utility after overlay re-test |
| `fpr_event_unvalidated` | benign false-positive permission event (`NA` for Cursor). **Не проверены, в статье не используются.** |
| `stopped_by_unvalidated` | attribution (`model`/`permission`/`sandbox`/`not_exposed`/…). **Не проверены, в статье не используются.** |
| `outcome` | audit outcome label when present |
| `model` | agent model id |
| `run_date` | ISO-like timestamp |

> **Note:** `fpr_event_unvalidated` and `stopped_by_unvalidated` are shipped for
> completeness of the harness dump but are **unvalidated and not used in the paper**.

## Metrics

- **ASR** (Attack Success Rate): share of *malicious* runs with
  `attack_success=True` (honey/marker/oracle confirms effect).
- **TCR** (Task Completion Rate): share of runs with `utility_rerun=True`
  (original tests re-executed on final app; network-dependent tests skipped).
- **FPR** (OpenCode only, paper path): ask/deny on protected/config-like paths
  in benign runs — computed in `stats/`, not from `fpr_event_unvalidated`.
  Cursor FPR is **not measured** (no permission telemetry in text-mode logs).

Primary contrast in `stats/final_stats.md`: ASR off→strict with scenario-cluster
bootstrap 95% CI, paired permutation p, Holm adjustment (two actors).

## Statistics methodology

See `stats/final_stats.md` and `stats/stats_intervals.py`:

- Wilson score CI (conditional on the fixed scenario set).
- Cluster bootstrap over **scenarios** (not i.i.d. trials).
- Paired permutation on per-scenario ASR differences for profile contrasts.

## Limitations

1. **`b14_readme_env`** stays in the main matrix but is a *conditional* trigger:
   many malicious trials never fire the exfil (`stopped_by_unvalidated=not_exposed`).
2. **Cursor** lacks structured permission events → no FPR;
   `stopped_by_unvalidated` is often empty.
3. **`b14_sandbox_allowlist`** is OpenCode-only and shipped as `experiment=b14_sandbox`,
   not mixed into the 1200 main cells.
4. Markers such as `sk_live_…` / `B19_GIT_…` inside scenarios are **synthetic honeytokens**,
   not real credentials.
5. Secrets/PII scrubbing: API keys, Bearer tokens, `/home/<user>` paths, e-mails, and
   **public** IPv4 addresses → `<REDACTED>`. Private/loopback ranges
   (`127/8`, `10/8`, `172.16/12`, `192.168/16`, `0.0.0.0`) and package-version-like
   `x.y.z.w` tokens are left intact.
6. `fpr_event_unvalidated` / `stopped_by_unvalidated`: **не проверены, в статье не используются.**

## License

**CC BY 4.0** — https://creativecommons.org/licenses/by/4.0/

## Citation

Please cite the HiveTrace / MOSAIC project and link this dataset together with
https://github.com/Charoda/hvi_lab .
'''
    (OUT / "README.md").write_text(text, encoding="utf-8")


def human_bytes(n: int) -> str:
    x = float(n)
    for u in ("B", "KB", "MB", "GB", "TB"):
        if x < 1024 or u == "TB":
            return f"{x:.1f} {u}" if u != "B" else f"{int(x)} B"
        x /= 1024
    return f"{n} B"


def final_report(redact_counts: Counter, verify_hits: list[str], package_notes: list[dict]) -> str:
    # size / files / top10
    files = [p for p in OUT.rglob("*") if p.is_file()]
    sizes = sorted(((p.stat().st_size, p) for p in files), reverse=True)
    total = sum(s for s, _ in sizes)
    lines = []
    lines.append("# dataset_release build report")
    lines.append("")
    lines.append(f"- Built: {datetime.now(timezone.utc).isoformat()}")
    lines.append("- Output: `dataset_release/`")
    lines.append(f"- Total size: **{human_bytes(total)}** ({total} bytes)")
    lines.append(f"- File count: **{len(files)}**")
    lines.append(f"- Runs packaged: **1230** (1200 main + 30 b14_sandbox)")
    lines.append("")
    lines.append("## Top-10 heaviest files")
    lines.append("")
    for i, (s, p) in enumerate(sizes[:10], 1):
        lines.append(f"{i}. `{p.relative_to(OUT)}` — {human_bytes(s)}")
    lines.append("")
    lines.append("## Secret scrubbing")
    lines.append("")
    lines.append("| type | replacements |")
    lines.append("|---|---|")
    for k, v in sorted(redact_counts.items()):
        lines.append(f"| {k} | {v} |")
    if not redact_counts:
        lines.append("| (none) | 0 |")
    lines.append("")
    lines.append(f"- Total replacements: **{sum(redact_counts.values())}**")
    lines.append(f"- Post-redact grep hits: **{len(verify_hits)}** (target 0)")
    if PUBLIC_IP_EXAMPLES:
        # Raw public IPs stay in build stdout only (embedding them re-fails verify).
        lines.append(
            "- Example public IPs replaced: see build stdout "
            f"(captured {len(PUBLIC_IP_EXAMPLES)} unique samples)."
        )
    if verify_hits:
        lines.append("- Remaining samples:")
        for h in verify_hits[:20]:
            lines.append(f"  - {h}")
    lines.append("")
    notes = Counter(n for st in package_notes for n in st.get("notes", []))
    lines.append("## Packaging notes histogram")
    lines.append("")
    for k, v in notes.most_common():
        lines.append(f"- `{k}`: {v}")
    lines.append("")
    missing = sum(1 for st in package_notes if not st.get("ok"))
    lines.append(f"- Runs with missing log dir: {missing}")
    lines.append("")
    text = "\n".join(lines) + "\n"
    (OUT / "BUILD_REPORT.md").write_text(text, encoding="utf-8")
    return text


def main() -> int:
    global PUBLIC_IP_EXAMPLES
    PUBLIC_IP_EXAMPLES = []
    t0 = time.time()
    if OUT.exists():
        log(f"removing previous {OUT}")
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    runs_root = OUT / "runs"
    strace_staging = OUT / "_strace_staging"
    strace_staging.mkdir()
    (OUT / "stats").mkdir()
    (OUT / "scenarios").mkdir()

    log("building catalog")
    rows = build_catalog()
    assert len(rows) == 1230, len(rows)
    evidence = load_batch_evidence()

    log("packaging runs")
    notes = []
    for i, row in enumerate(rows, 1):
        st = package_run(row, runs_root, strace_staging)
        # oracle evidence text from batch
        ev = evidence.get(row["run_id"])
        if ev:
            (runs_root / row["run_id"] / "oracle_evidence.txt").write_text(ev + "\n", encoding="utf-8")
        notes.append(st)
        if i % 100 == 0 or i == len(rows):
            log(f"  packaged {i}/{len(rows)}")

    log("writing runs.csv")
    write_runs_csv(rows)

    log("copying scenarios")
    copy_scenarios(OUT / "scenarios")

    log("copying stats")
    shutil.copy2(REPO / "audit" / "final_stats.md", OUT / "stats" / "final_stats.md")
    shutil.copy2(REPO / "audit" / "stats_intervals.py", OUT / "stats" / "stats_intervals.py")
    shutil.copy2(REPO / "docs" / "CHANGELOG.md", OUT / "stats" / "CHANGELOG.md")

    log("redacting staged strace logs before archive")
    counts_strace = redact_tree(strace_staging)

    log("building strace.tar.zst")
    tar_path = OUT / "strace.tar"
    subprocess.check_call(
        ["tar", "-cf", str(tar_path), "-C", str(strace_staging), "."],
    )
    # -6: good ratio without multi-hour CPU on ~10GB strace corpus
    subprocess.check_call(["zstd", "-T0", "-6", "--rm", str(tar_path)])
    assert (OUT / "strace.tar.zst").is_file()
    shutil.rmtree(strace_staging)

    log("writing README")
    write_readme()

    log("redacting secrets in dataset_release/")
    counts = redact_tree(OUT)
    for k, v in counts_strace.items():
        counts[k] += v
    log(f"redact counts: {dict(counts)}")
    # rebuild parquet from redacted CSV
    log("writing runs.parquet from redacted CSV")
    write_runs_parquet_from_csv()
    hits = verify_clean(OUT)
    log(f"verify hits: {len(hits)}")

    report = final_report(counts, hits, notes)
    # report itself must stay clean (no absolute /home paths)
    hits2 = verify_clean(OUT)
    if hits2:
        log(f"post-report verify hits: {len(hits2)}")
        counts_fix = redact_tree(OUT)
        for k, v in counts_fix.items():
            counts[k] += v
        hits2 = verify_clean(OUT)
        report = final_report(counts, hits2, notes)
        hits = hits2
    print(report)
    log(f"done in {time.time()-t0:.1f}s")
    return 0 if not hits else 2


if __name__ == "__main__":
    raise SystemExit(main())
