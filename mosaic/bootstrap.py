"""Repo-local initialization helpers for ABC-Bench benchmark apps."""

from __future__ import annotations

import importlib
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

from .dataset import DATASET_WORKBOOK, load_dataset_task_ids
from .tasks import DEFAULT_APPS_DIR, REPO_ROOT

OVERLAYS_DIR = REPO_ROOT / "benchmark" / "overlays"

HF_DATASET_REPO = "MosaicBenchmark/mosaic-bench"
HF_DATASET_URL = f"https://huggingface.co/datasets/{HF_DATASET_REPO}"
BENCHMARK_TASK_IDS_FILE = DATASET_WORKBOOK
BENCHMARK_CHAIN_IDS_FILE = DATASET_WORKBOOK
STARTER_CHAIN_IDS_FILE = REPO_ROOT / "benchmark" / "chains" / "starter_subset.txt"


def _run(cmd: list[str], *, cwd: Path | None = None, timeout: int = 1800) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _git_lfs_available() -> tuple[bool, str | None]:
    if not shutil.which("git"):
        return False, "git is not installed."
    if not shutil.which("git-lfs") and not shutil.which("git"):
        return False, "git-lfs is not installed."
    result = _run(["git", "lfs", "version"], timeout=20)
    if result.returncode != 0:
        return False, (result.stderr or result.stdout or "git lfs probe failed.").strip()
    return True, None


def _snapshot_available() -> tuple[bool, str | None]:
    try:
        importlib.import_module("huggingface_hub")
    except Exception as exc:
        return False, str(exc)
    return True, None


def _choose_method(method: str) -> str:
    if method != "auto":
        return method
    snapshot_ok, _ = _snapshot_available()
    if snapshot_ok:
        return "snapshot"
    git_lfs_ok, _ = _git_lfs_available()
    if git_lfs_ok:
        return "git-lfs"
    raise RuntimeError(
        "Could not auto-select an ABC-Bench download method. Install `huggingface_hub` "
        "or `git-lfs`, or run `mosaic init --method ...` explicitly."
    )


def _download_with_snapshot(download_dir: Path) -> Path:
    try:
        from huggingface_hub import snapshot_download
    except Exception as exc:  # pragma: no cover - import path
        raise RuntimeError(
            "snapshot method requires `huggingface_hub`. Install it with `pip install huggingface_hub`."
        ) from exc

    local_dir = download_dir / "snapshot"
    # Only fetch the apps tarball — the dataset also ships chain definitions,
    # croissant metadata, etc. that aren't needed for `mosaic init`. Pulling
    # the full snapshot wastes bandwidth and trips HF's per-IP rate limit
    # (5000 file resolves / 5 min) when many machines init simultaneously.
    snapshot_download(
        repo_id=HF_DATASET_REPO,
        repo_type="dataset",
        local_dir=str(local_dir),
        allow_patterns=["tasks.tar.gz"],
    )
    return local_dir


def _download_with_git_lfs(download_dir: Path) -> Path:
    ok, error = _git_lfs_available()
    if not ok:
        raise RuntimeError(
            "git-lfs method requires Git LFS. Install it and run `git lfs install`.\n"
            f"Probe error: {error}"
        )

    repo_dir = download_dir / "repo"
    install = _run(["git", "lfs", "install"], cwd=download_dir, timeout=60)
    if install.returncode != 0:
        raise RuntimeError(f"`git lfs install` failed: {(install.stderr or install.stdout).strip()}")

    clone = _run(["git", "clone", HF_DATASET_URL, str(repo_dir)], cwd=download_dir, timeout=1800)
    if clone.returncode != 0:
        raise RuntimeError(f"`git clone` failed: {(clone.stderr or clone.stdout).strip()}")

    pull = _run(["git", "lfs", "pull"], cwd=repo_dir, timeout=1800)
    if pull.returncode != 0:
        raise RuntimeError(f"`git lfs pull` failed: {(pull.stderr or pull.stdout).strip()}")
    return repo_dir


def _find_tasks_archive(download_root: Path) -> Path:
    candidates = [
        download_root / "tasks.tar.gz",
        download_root / "snapshot" / "tasks.tar.gz",
        download_root / "repo" / "tasks.tar.gz",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    matches = sorted(download_root.rglob("tasks.tar.gz"))
    if matches:
        return matches[0]
    raise FileNotFoundError(f"Could not find tasks.tar.gz under {download_root}")


def _ensure_real_archive(archive_path: Path) -> None:
    head = archive_path.read_bytes()[:200]
    if head.startswith(b"version https://git-lfs.github.com/spec"):
        raise RuntimeError(
            f"{archive_path} is still a Git LFS pointer, not the real archive. "
            "Re-run `git lfs pull` or use `mosaic init --method snapshot`."
        )


def _member_task_id(member_name: str) -> str | None:
    parts = Path(member_name).parts
    if len(parts) < 2:
        return None
    if parts[0] != "tasks":
        return None
    task_id = parts[1]
    if not task_id.startswith("task_"):
        return None
    return task_id


def _load_ids(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text().splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def load_benchmark_task_ids() -> set[str]:
    """Return the benchmark app IDs used by the workbook-backed dataset."""
    if BENCHMARK_TASK_IDS_FILE.exists():
        return load_dataset_task_ids(BENCHMARK_TASK_IDS_FILE)

    from .chain_registry import load_chains

    # Fallback only if the workbook is missing.
    return {chain.task_id for chain in load_chains() if chain.task_id}


def _selected_task_ids(subset: str) -> set[str] | None:
    if subset == "all":
        return None

    from .chain_registry import load_chains

    chains = load_chains()
    if subset == "benchmark":
        return load_benchmark_task_ids()

    if subset == "active-chains":
        return {chain.task_id for chain in chains if chain.task_id}

    if subset == "starter":
        starter_chain_ids = set(_load_ids(STARTER_CHAIN_IDS_FILE))
        return {
            chain.task_id
            for chain in chains
            if chain.chain_id in starter_chain_ids and chain.task_id
        }

    raise ValueError(f"Unknown subset: {subset}")


def _safe_extract_member(tar: tarfile.TarFile, member: tarfile.TarInfo, destination: Path) -> None:
    target = (destination / member.name).resolve()
    if destination.resolve() not in target.parents and target != destination.resolve():
        raise RuntimeError(f"Refusing to extract suspicious archive path: {member.name}")
    tar.extract(member, path=destination)


def _extract_archive(archive_path: Path, extract_root: Path, *, selected_task_ids: set[str] | None) -> Path:
    with tarfile.open(archive_path, "r:gz") as tar:
        members = tar.getmembers()
        if selected_task_ids is not None:
            members = [
                member
                for member in members
                if _member_task_id(member.name) in selected_task_ids
            ]
        if not members:
            raise RuntimeError("No benchmark apps matched the requested subset.")
        for member in members:
            _safe_extract_member(tar, member, extract_root)

    extracted = extract_root / "tasks"
    if not extracted.is_dir():
        raise RuntimeError(f"Extracted archive did not contain a top-level tasks/ directory under {extract_root}")
    return extracted


def _apply_overlays(apps_dir: Path) -> None:
    """Copy version-controlled overlay files on top of downloaded apps."""
    if not OVERLAYS_DIR.is_dir():
        return
    for task_dir in OVERLAYS_DIR.iterdir():
        if not task_dir.is_dir():
            continue
        target = apps_dir / task_dir.name
        if target.is_dir():
            shutil.copytree(task_dir, target, dirs_exist_ok=True)


def _clear_destination(apps_dir: Path) -> None:
    apps_dir.mkdir(parents=True, exist_ok=True)
    for child in apps_dir.iterdir():
        if child.name == ".gitignore":
            continue
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def _copy_apps(extracted_dir: Path, apps_dir: Path, *, selected_task_ids: set[str] | None) -> int:
    apps_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    for task_path in sorted(extracted_dir.iterdir()):
        if not task_path.is_dir():
            continue
        if selected_task_ids is not None and task_path.name not in selected_task_ids:
            continue
        shutil.copytree(task_path, apps_dir / task_path.name)
        count += 1
    return count


def init_benchmark_apps(
    *,
    apps_dir: str | Path | None = None,
    method: str = "auto",
    subset: str = "benchmark",
    force: bool = False,
    plan_only: bool = False,
) -> dict[str, object]:
    """Download and extract repo-local ABC-Bench benchmark apps."""
    resolved_apps_dir = Path(apps_dir) if apps_dir else DEFAULT_APPS_DIR
    selected_task_ids = _selected_task_ids(subset)
    chosen_method = _choose_method(method)
    required_external_tools = ["docker", "python3"]
    if chosen_method == "snapshot":
        required_external_tools.append("huggingface_hub")
    elif chosen_method == "git-lfs":
        required_external_tools.extend(["git", "git-lfs"])

    existing_items = [
        path for path in resolved_apps_dir.iterdir()
        if resolved_apps_dir.exists() and path.name != ".gitignore"
    ] if resolved_apps_dir.exists() else []
    if existing_items and not force:
        raise RuntimeError(
            f"{resolved_apps_dir} already contains files. Re-run with --force to replace the current benchmark apps."
        )

    if plan_only:
        return {
            "dataset_repo": HF_DATASET_REPO,
            "dataset_url": HF_DATASET_URL,
            "apps_dir": str(resolved_apps_dir),
            "method": chosen_method,
            "subset": subset,
            "app_count": len(selected_task_ids) if selected_task_ids is not None else None,
            "sample_apps": sorted(selected_task_ids)[:5] if selected_task_ids is not None else [],
            "subset_task_ids": sorted(selected_task_ids) if selected_task_ids is not None else None,
            "required_external_tools": required_external_tools,
            "plan_only": True,
            "benchmark_source": str(BENCHMARK_TASK_IDS_FILE.relative_to(REPO_ROOT)) if BENCHMARK_TASK_IDS_FILE.exists() else "chain_registry_fallback",
        }

    with tempfile.TemporaryDirectory(prefix="mosaic-init-") as tmp:
        temp_root = Path(tmp)
        download_root = temp_root / "download"
        download_root.mkdir(parents=True, exist_ok=True)

        if chosen_method == "snapshot":
            _download_with_snapshot(download_root)
        elif chosen_method == "git-lfs":
            _download_with_git_lfs(download_root)
        else:  # pragma: no cover - guarded by _choose_method
            raise RuntimeError(f"Unsupported init method: {chosen_method}")

        archive_path = _find_tasks_archive(download_root)
        _ensure_real_archive(archive_path)

        extract_root = temp_root / "extract"
        extract_root.mkdir(parents=True, exist_ok=True)
        extracted_dir = _extract_archive(
            archive_path,
            extract_root,
            selected_task_ids=selected_task_ids,
        )

        _clear_destination(resolved_apps_dir)
        app_count = _copy_apps(
            extracted_dir,
            resolved_apps_dir,
            selected_task_ids=selected_task_ids,
        )

    _apply_overlays(resolved_apps_dir)

    sample = [path.name for path in sorted(resolved_apps_dir.iterdir()) if path.is_dir()][:5]
    return {
        "dataset_repo": HF_DATASET_REPO,
        "dataset_url": HF_DATASET_URL,
        "apps_dir": str(resolved_apps_dir),
        "method": chosen_method,
        "subset": subset,
        "app_count": app_count,
        "sample_apps": sample,
        "required_external_tools": required_external_tools,
        "plan_only": False,
        "benchmark_source": str(BENCHMARK_TASK_IDS_FILE.relative_to(REPO_ROOT)) if BENCHMARK_TASK_IDS_FILE.exists() else "chain_registry_fallback",
    }


def render_init_report(report: dict[str, object]) -> str:
    """Render a concise human-readable init report."""
    lines = [
        "Planned ABC-Bench benchmark app install for MOSAIC."
        if report.get("plan_only")
        else "Initialized ABC-Bench benchmark apps for MOSAIC.",
        "",
        f"Dataset:  {report['dataset_repo']}",
        f"Method:   {report['method']}",
        f"Subset:   {report['subset']}",
        f"Apps dir: {report['apps_dir']}",
    ]
    app_count = report.get("app_count")
    lines.append(f"Apps:     {app_count if app_count is not None else 'all'}")
    sample = report.get("sample_apps") or []
    if sample:
        lines.append(f"Sample:   {', '.join(sample)}")
    tools = report.get("required_external_tools") or []
    if tools:
        lines.append(f"Requires: {', '.join(tools)}")
    lines.extend([
        "",
        "Next:",
        "  Manual install is the public default; `mosaic init` is the convenience wrapper.",
        "  mosaic doctor --agents codex",
        "  mosaic validate",
        "  mosaic batch --manifest benchmark/manifests/submission-smoke.batch.json",
    ])
    return "\n".join(lines)


def render_init_json(report: dict[str, object]) -> str:
    return json.dumps(report, indent=2)
