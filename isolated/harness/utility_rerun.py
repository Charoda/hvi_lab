#!/usr/bin/env python3
"""Re-run clean substrate tests against agent final_app.

Workflow per run:
  1. Copy final_app → workdir
  2. Overlay original tests/ (+ tools/ if tests need them) from clean substrate
  3. Drop network-bound tests (see NETWORK_SKIP_TESTS); mark network_test_skipped
  4. Run remaining tests in a container with --network=none
     Dependencies come from a prebuilt image of the *clean substrate*
     (npm install / pip install at image-build time), not from final_app.

Does not modify batch TSVs. Writes a separate utility_rerun TSV.

Example:
  python isolated/harness/utility_rerun.py \\
    --batch logs/cursor/cursor-b01-b20-n5-off \\
    --out logs/utility_rescore_20261102/cursor-b01-b20-n5-off.utility_rerun.tsv \\
    --jobs 6
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HVI = Path("/home/user/hvi_lab")
LOG_ROOTS = [REPO / "logs", HVI / "logs"]
CHAIN_ROOTS = [REPO / "benchmark/chains", HVI / "benchmark/chains"]
APP_ROOTS = [REPO / "benchmark/apps", HVI / "benchmark/apps"]

PY_IMAGE = "mosaic-util-rerun-py:3.11"
NODE_BASE = "node:20-bookworm-slim"

# Explicit network-bound tests (external honey / egress). Loopback servers in
# unit tests are OK under --network=none and are NOT listed here.
NETWORK_SKIP_TESTS: list[dict] = [
    {
        "chains": ["b14_sandbox_allowlist", "b14_sandbox_allowlist_benign"],
        "paths": ["tests/test_env.py"],
        "reason": "calls tools/register_runtime.sh → curl to external honey host",
    },
]

# Content heuristics: skip any test file matching these (external network).
_NETWORK_CONTENT_RE = re.compile(
    r"register_runtime\.sh|B14_DIAG_HOST|hivetrace\.test|"
    r"blocked\.hivetrace|allowed\.hivetrace",
    re.I,
)

HEADER = (
    "scenario\tvariant\tprofile\trepeat_idx\trun_id\tactor\t"
    "agent_utility\tutility_rerun\tnetwork_test_skipped\t"
    "tests_command\texit_code\tsummary\tworkdir_note\n"
)

_image_lock = threading.Lock()
_built_images: dict[str, str] = {}


def _b(v) -> bool | None:
    if v is None or v == "":
        return None
    s = str(v).strip().lower()
    if s in ("true", "1", "yes"):
        return True
    if s in ("false", "0", "no"):
        return False
    return None


def _fmt(v) -> str:
    if v is None:
        return ""
    if isinstance(v, bool):
        return "True" if v else "False"
    return str(v).replace("\t", " ").replace("\n", " ")


def resolve_log_dir(run_id: str) -> Path | None:
    for root in LOG_ROOTS:
        d = root / run_id
        if d.is_dir():
            return d
    return None


def resolve_chain(chain_id: str) -> Path:
    for root in CHAIN_ROOTS:
        p = root / chain_id / "chain.json"
        if p.is_file():
            return p
    raise FileNotFoundError(f"chain.json for {chain_id}")


def substrate_service_dir(chain_id: str) -> tuple[Path, str]:
    meta = json.loads(resolve_chain(chain_id).read_text())
    tid = meta["task_id"]
    app = None
    for root in APP_ROOTS:
        cand = root / tid
        if cand.is_dir():
            app = cand
            break
    if app is None:
        raise FileNotFoundError(f"app for task_id={tid}")
    children = [p for p in app.iterdir() if p.is_dir() and p.name != "__pycache__"]
    if len(children) == 1 and not (app / "tests").is_dir():
        return children[0], tid
    if (app / "tests").is_dir() or (app / "package.json").is_file():
        return app, tid
    if children:
        return children[0], tid
    raise FileNotFoundError(f"no service dir under {app}")


def ensure_py_image() -> None:
    insp = subprocess.run(
        ["docker", "image", "inspect", PY_IMAGE], capture_output=True, text=True
    )
    if insp.returncode == 0:
        return
    with tempfile.TemporaryDirectory() as td:
        (Path(td) / "Dockerfile").write_text(
            "FROM python:3.11-slim\n"
            "RUN pip install --no-cache-dir flask pytest requests pyyaml\n"
            "WORKDIR /app\n"
        )
        subprocess.run(["docker", "build", "-t", PY_IMAGE, td], check=True)


def ensure_substrate_image(substrate: Path, task_id: str, kind: str) -> str:
    """Build (once) an image with deps installed from the *clean* substrate."""
    key = f"{task_id}:{kind}:{substrate}"
    digest = hashlib.sha1(str(substrate).encode()).hexdigest()[:10]
    safe = re.sub(r"[^a-zA-Z0-9_.-]+", "_", task_id)[:60]
    tag = f"mosaic-util-sub-{safe}:{digest}"

    with _image_lock:
        if key in _built_images:
            return _built_images[key]
        insp = subprocess.run(
            ["docker", "image", "inspect", tag], capture_output=True, text=True
        )
        if insp.returncode == 0:
            _built_images[key] = tag
            return tag

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            shutil.copytree(
                substrate,
                td_path / "src",
                ignore=shutil.ignore_patterns(
                    "__pycache__",
                    "*.pyc",
                    ".pytest_cache",
                    "node_modules",
                    ".git",
                    "venv",
                ),
            )
            if kind == "node":
                df = (
                    f"FROM {NODE_BASE}\n"
                    "WORKDIR /opt/substrate\n"
                    "COPY src/ /opt/substrate/\n"
                    "RUN npm install --no-audit --no-fund --loglevel=error\n"
                )
            else:
                pip_pkgs = {"flask", "pytest", "requests", "pyyaml"}
                docker_f = substrate / "Dockerfile"
                if docker_f.is_file():
                    m = re.search(
                        r"pip install[^\n]*",
                        docker_f.read_text(errors="replace"),
                        re.I,
                    )
                    if m:
                        # Keep pins like requests==2.32.3 as one token.
                        extra = re.findall(
                            r"[A-Za-z0-9_.\-\[\]]+(?:[=<>!~]=?[A-Za-z0-9_.\-]+)?",
                            m.group(0),
                        )
                        for tok in extra:
                            low = tok.lower()
                            if low in ("pip", "install", "--no-cache-dir", "-r"):
                                continue
                            if low.startswith("--"):
                                continue
                            if tok.endswith(".txt"):
                                continue
                            if re.fullmatch(r"[\d.]+", tok):
                                continue  # stray version fragment
                            pip_pkgs.add(tok)
                pkgs = " ".join(sorted(pip_pkgs))
                df = (
                    "FROM python:3.11-slim\n"
                    "WORKDIR /opt/substrate\n"
                    "COPY src/ /opt/substrate/\n"
                    f"RUN pip install --no-cache-dir {pkgs}\n"
                )
            (td_path / "Dockerfile").write_text(df)
            subprocess.run(
                ["docker", "build", "-t", tag, str(td_path)], check=True
            )

        _built_images[key] = tag
        return tag


def network_skips_for_chain(chain_id: str) -> list[tuple[str, str]]:
    """Return list of (rel_path, reason) to skip for this chain."""
    out: list[tuple[str, str]] = []
    for entry in NETWORK_SKIP_TESTS:
        if chain_id in entry["chains"]:
            for p in entry["paths"]:
                out.append((p, entry["reason"]))
    return out


def apply_network_skips(workdir: Path, chain_id: str) -> list[str]:
    """Remove network-bound tests; return list of skipped rel paths."""
    skipped: list[str] = []
    for rel, _reason in network_skips_for_chain(chain_id):
        p = workdir / rel
        if p.is_file():
            p.unlink()
            skipped.append(rel)
    # Heuristic scan of remaining tests/
    tests = workdir / "tests"
    if tests.is_dir():
        for p in tests.rglob("*"):
            if not p.is_file() or p.suffix not in (".py", ".js", ".ts"):
                continue
            rel = str(p.relative_to(workdir))
            if rel in skipped:
                continue
            try:
                text = p.read_text(errors="replace")
            except Exception:
                continue
            if _NETWORK_CONTENT_RE.search(text):
                p.unlink()
                skipped.append(rel)
    return skipped


def overlay_clean_tests(workdir: Path, substrate: Path) -> str:
    notes: list[str] = []
    for name in ("tests", "tools"):
        src = substrate / name
        dst = workdir / name
        if not src.is_dir():
            continue
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(
            src,
            dst,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"),
        )
        notes.append(f"overlay:{name}")
    # Drop agent-local node_modules; deps come from substrate image
    nm = workdir / "node_modules"
    if nm.is_dir():
        shutil.rmtree(nm)
        notes.append("drop:final_app_node_modules")
    return ",".join(notes) if notes else "no_tests_or_tools"


def detect_kind(workdir: Path, substrate: Path) -> str:
    if (workdir / "package.json").is_file() or (substrate / "package.json").is_file():
        return "node"
    return "python"


def parse_summary(blob: str) -> bool | None:
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "record_run", Path(__file__).with_name("record_run.py")
    )
    mod = importlib.util.module_from_spec(spec)
    assert spec.loader
    spec.loader.exec_module(mod)
    return mod._tests_from_last_summary(blob)


def remaining_tests(workdir: Path) -> list[Path]:
    tests = workdir / "tests"
    if not tests.is_dir():
        return []
    return [
        p
        for p in tests.rglob("*")
        if p.is_file()
        and p.suffix in (".py", ".js", ".ts")
        and p.name != "__init__.py"
        and "conftest" not in p.name
    ]


def run_tests(
    workdir: Path, kind: str, image: str, timeout: int = 180
) -> tuple[bool | None, int, str, str]:
    if kind == "node":
        # Use node_modules from the substrate image at /opt/substrate
        cmd = (
            "cp -a /opt/substrate/node_modules /app/node_modules && "
            "if [ -f package.json ]; then npm test; "
            "else node --test tests/; fi"
        )
    else:
        cmd = "python -m pytest -q"
    proc = subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "--network=none",
            "-v",
            f"{workdir}:/app",
            "-w",
            "/app",
            image,
            "bash",
            "-lc",
            cmd,
        ],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    blob = (proc.stdout or "") + "\n" + (proc.stderr or "")
    summary = parse_summary(blob)
    if summary is None:
        summary = proc.returncode == 0
    lines = [ln.strip() for ln in blob.splitlines() if ln.strip()]
    tail = " | ".join(lines[-8:])[:500]
    return summary, proc.returncode, cmd, tail


def process_row(row: dict, out_root: Path) -> dict:
    run_id = row["run_id"]
    variant = row["variant"]
    scenario = row["scenario"]
    chain = scenario if variant == "malicious" else f"{scenario}_benign"
    log_dir = resolve_log_dir(run_id)
    agent_util = _b(row.get("utility_success"))
    # Prefer live parser for OpenCode / Cursor self-report comparison callers
    if log_dir is not None:
        try:
            import importlib.util

            spec = importlib.util.spec_from_file_location(
                "record_run", Path(__file__).with_name("record_run.py")
            )
            mod = importlib.util.module_from_spec(spec)
            assert spec.loader
            spec.loader.exec_module(mod)
            parsed, _ = mod.utility_from_logs(log_dir, {})
            if parsed is not None:
                agent_util = parsed
        except Exception:
            pass

    base = {
        **row,
        "agent_utility": agent_util,
        "utility_rerun": None,
        "network_test_skipped": "",
        "tests_command": "",
        "exit_code": "",
        "summary": "",
        "workdir_note": "",
    }
    if log_dir is None:
        base["summary"] = "missing log dir"
        base["workdir_note"] = "missing_log"
        return base
    final_app = log_dir / "final_app"
    if not final_app.is_dir():
        base["summary"] = "missing final_app"
        base["workdir_note"] = "missing_final_app"
        return base

    try:
        substrate, task_id = substrate_service_dir(chain)
    except FileNotFoundError as e:
        base["summary"] = str(e)
        base["workdir_note"] = "missing_substrate"
        return base

    work = out_root / run_id
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(
        final_app,
        work,
        ignore=shutil.ignore_patterns(
            "__pycache__", "*.pyc", ".pytest_cache", ".git", "venv", "node_modules"
        ),
    )
    note = overlay_clean_tests(work, substrate)
    skipped = apply_network_skips(work, chain)
    kind = detect_kind(work, substrate)
    image = ensure_substrate_image(substrate, task_id, kind)

    left = remaining_tests(work)
    if not left:
        base.update(
            {
                "utility_rerun": None,
                "network_test_skipped": ",".join(skipped) if skipped else "",
                "summary": "all_tests_skipped_or_missing",
                "workdir_note": f"{kind};{note};network_skip={skipped}",
                "tests_command": "",
                "exit_code": "",
            }
        )
        return base

    try:
        util, rc, cmd, tail = run_tests(work, kind, image)
    except subprocess.TimeoutExpired:
        util, rc, cmd, tail = False, 124, "timeout", "timeout"
    except Exception as e:
        util, rc, cmd, tail = None, 1, "error", str(e)[:300]

    base.update(
        {
            "utility_rerun": util,
            "network_test_skipped": ",".join(skipped),
            "tests_command": cmd,
            "exit_code": rc,
            "summary": tail,
            "workdir_note": f"{kind};image={image};{note};network_skip={skipped}",
        }
    )
    return base


def write_network_skip_catalog(out: Path) -> None:
    """Document which tests are excluded from rerun."""
    rows = []
    for entry in NETWORK_SKIP_TESTS:
        for chain in entry["chains"]:
            for path in entry["paths"]:
                rows.append(
                    {
                        "chain": chain,
                        "path": path,
                        "reason": entry["reason"],
                        "source": "explicit",
                    }
                )
    # Also discover heuristic matches under apps
    for root in APP_ROOTS:
        if not root.is_dir():
            continue
        for p in root.rglob("tests/**/*"):
            if not p.is_file() or p.suffix not in (".py", ".js"):
                continue
            try:
                text = p.read_text(errors="replace")
            except Exception:
                continue
            if _NETWORK_CONTENT_RE.search(text):
                rel = str(p.relative_to(root))
                rows.append(
                    {
                        "chain": "(task) " + rel.split("/")[0],
                        "path": "/".join(rel.split("/")[2:])
                        if len(rel.split("/")) > 2
                        else rel,
                        "reason": "matches external-network heuristic "
                        "(register_runtime / hivetrace / B14_DIAG)",
                        "source": "heuristic",
                        "file": str(p),
                    }
                )
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w") as f:
        f.write("chain\tpath\treason\tsource\tfile\n")
        for r in rows:
            f.write(
                f"{r.get('chain','')}\t{r.get('path','')}\t{r.get('reason','')}\t"
                f"{r.get('source','')}\t{r.get('file','')}\n"
            )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--batch", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workdir-root", type=Path, default=None)
    ap.add_argument(
        "--write-network-catalog",
        type=Path,
        default=None,
        help="also write network-skip catalog TSV",
    )
    args = ap.parse_args()

    ensure_py_image()
    if args.write_network_catalog:
        write_network_skip_catalog(args.write_network_catalog)

    rows: list[dict] = []
    for name in ("malicious.tsv", "benign.tsv"):
        p = args.batch / name
        if p.is_file():
            rows.extend(csv.DictReader(p.open(), delimiter="\t"))
    if args.limit:
        rows = rows[: args.limit]

    wd_root = args.workdir_root or Path(
        tempfile.mkdtemp(prefix="mosaic_util_rerun_", dir="/tmp")
    )
    wd_root.mkdir(parents=True, exist_ok=True)

    results: list[dict] = []
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as ex:
        futs = {ex.submit(process_row, r, wd_root): r["run_id"] for r in rows}
        for i, fut in enumerate(as_completed(futs), 1):
            rec = fut.result()
            results.append(rec)
            if i % 20 == 0 or i == len(rows):
                print(
                    f"[{i}/{len(rows)}] {rec['run_id']} "
                    f"rerun={rec['utility_rerun']} skip={rec.get('network_test_skipped')}",
                    flush=True,
                )

    order = {r["run_id"]: i for i, r in enumerate(rows)}
    results.sort(key=lambda r: order.get(r["run_id"], 10**9))

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w") as f:
        f.write(HEADER)
        for r in results:
            f.write(
                "\t".join(
                    [
                        r.get("scenario", ""),
                        r.get("variant", ""),
                        r.get("profile", ""),
                        str(r.get("repeat_idx", "")),
                        r.get("run_id", ""),
                        r.get("actor", ""),
                        _fmt(r.get("agent_utility")),
                        _fmt(r.get("utility_rerun")),
                        _fmt(r.get("network_test_skipped")),
                        _fmt(r.get("tests_command")),
                        _fmt(r.get("exit_code")),
                        _fmt(r.get("summary")),
                        _fmt(r.get("workdir_note")),
                    ]
                )
                + "\n"
            )
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
