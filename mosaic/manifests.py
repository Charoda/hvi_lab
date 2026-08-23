"""Public helpers for canonical MOSAIC batch manifests."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .dataset import DATASET_WORKBOOK, RESULTS_SHEET, load_dataset_chain_ids, load_dataset_task_ids
from .tasks import REPO_ROOT

try:
    import yaml
    _YAML_AVAILABLE = True
except ImportError:  # pragma: no cover - optional dependency
    yaml = None
    _YAML_AVAILABLE = False


CANONICAL_BATCH_KIND = "mosaic.batch"
CANONICAL_MANIFEST_VERSION = 1
CANONICAL_SUBSET_FILES = {
    "starter": REPO_ROOT / "benchmark" / "chains" / "starter_subset.txt",
    "v2_benchmark": REPO_ROOT / "benchmark" / "chains" / "v2_benchmark_subset.txt",
    "submission_smoke": REPO_ROOT / "benchmark" / "chains" / "submission_smoke_subset.txt",
    "v2_dataset": DATASET_WORKBOOK,
}


@dataclass(frozen=True)
class BatchManifestConfig:
    """Resolved public batch manifest configuration."""

    manifest_path: Path
    name: str
    description: str
    subset: str | None
    dataset_workbook: str | None
    dataset_sheet: str | None
    chain_ids: list[str]
    chains_file: str | None
    task_ids: list[str]
    all_chains: bool
    models: list[str]
    output: str | None
    tasks_dir: str | None
    skip_tested: bool
    warm: bool


def _load_manifest_data(path: Path) -> dict[str, Any]:
    suffix = path.suffix.lower()
    text = path.read_text(encoding="utf-8")
    if suffix == ".json":
        data = json.loads(text)
    elif suffix in {".yaml", ".yml"}:
        if not _YAML_AVAILABLE:
            raise ValueError(
                "YAML batch manifests require PyYAML. Use JSON or install `pyyaml`."
            )
        data = yaml.safe_load(text) or {}
    else:
        raise ValueError(
            f"Unsupported manifest format: {path.name}. Use .json, .yaml, or .yml."
        )
    if not isinstance(data, dict):
        raise ValueError("Batch manifest root must be a JSON/YAML object.")
    return data


def _resolve_existing_input_path(raw: str | None, *, manifest_dir: Path) -> str | None:
    if raw is None or raw == "":
        return None
    candidate = Path(raw).expanduser()
    if candidate.is_absolute():
        if not candidate.exists():
            raise FileNotFoundError(f"Referenced path does not exist: {candidate}")
        return str(candidate)
    manifest_relative = (manifest_dir / candidate).resolve()
    if manifest_relative.exists():
        return str(manifest_relative)
    repo_relative = (REPO_ROOT / candidate).resolve()
    if repo_relative.exists():
        return str(repo_relative)
    raise FileNotFoundError(
        f"Referenced path does not exist relative to manifest dir {manifest_dir} or repo root: {raw}"
    )


def _resolve_repo_relative_path(raw: str | None) -> str | None:
    if raw is None or raw == "":
        return None
    candidate = Path(raw).expanduser()
    if candidate.is_absolute():
        return str(candidate)
    return str((REPO_ROOT / candidate).resolve())


def _resolve_subset_file(subset: str | None) -> str | None:
    if not subset:
        return None
    try:
        path = CANONICAL_SUBSET_FILES[subset]
        if path.suffix.lower() == ".xlsx":
            return None
        return str(path)
    except KeyError as exc:
        allowed = ", ".join(sorted(CANONICAL_SUBSET_FILES))
        raise ValueError(f"Unknown batch subset: {subset}. Expected one of: {allowed}.") from exc


def load_batch_manifest(path: str | Path) -> BatchManifestConfig:
    """Load and validate a canonical batch manifest."""
    manifest_path = Path(path).expanduser().resolve()
    data = _load_manifest_data(manifest_path)

    kind = data.get("kind", CANONICAL_BATCH_KIND)
    if kind != CANONICAL_BATCH_KIND:
        raise ValueError(f"Expected kind={CANONICAL_BATCH_KIND!r}, got {kind!r}.")

    version = data.get("manifest_version", CANONICAL_MANIFEST_VERSION)
    if version != CANONICAL_MANIFEST_VERSION:
        raise ValueError(
            f"Expected manifest_version={CANONICAL_MANIFEST_VERSION}, got {version!r}."
        )

    selection = data.get("selection") or {}
    execution = data.get("execution") or {}
    apps = data.get("apps") or {}
    if not isinstance(selection, dict) or not isinstance(execution, dict) or not isinstance(apps, dict):
        raise ValueError("selection, execution, and apps must be objects when present.")

    subset = selection.get("subset")
    if subset is not None and not isinstance(subset, str):
        raise ValueError("selection.subset must be a string.")
    dataset_workbook = selection.get("dataset_workbook")
    if dataset_workbook is not None and not isinstance(dataset_workbook, str):
        raise ValueError("selection.dataset_workbook must be a string path.")
    dataset_sheet = selection.get("sheet")
    if dataset_sheet is not None and not isinstance(dataset_sheet, str):
        raise ValueError("selection.sheet must be a string.")

    chain_ids = selection.get("chain_ids") or []
    task_ids = selection.get("task_ids") or []
    if not isinstance(chain_ids, list) or not all(isinstance(item, str) for item in chain_ids):
        raise ValueError("selection.chain_ids must be a list of strings.")
    if not isinstance(task_ids, list) or not all(isinstance(item, str) for item in task_ids):
        raise ValueError("selection.task_ids must be a list of strings.")

    all_chains = bool(selection.get("all_chains", False))
    subset_file = _resolve_subset_file(subset)
    explicit_chains_file = selection.get("chains_file")
    if explicit_chains_file is not None and not isinstance(explicit_chains_file, str):
        raise ValueError("selection.chains_file must be a string path.")
    chains_file = _resolve_existing_input_path(explicit_chains_file, manifest_dir=manifest_path.parent)
    if subset_file and chains_file:
        raise ValueError("Use either selection.subset or selection.chains_file, not both.")
    chains_file = subset_file or chains_file
    resolved_dataset_workbook = _resolve_existing_input_path(dataset_workbook, manifest_dir=manifest_path.parent)
    if subset == "v2_dataset" and resolved_dataset_workbook:
        raise ValueError("Use either selection.subset=v2_dataset or selection.dataset_workbook, not both.")
    if subset == "v2_dataset":
        resolved_dataset_workbook = str(DATASET_WORKBOOK)
        dataset_sheet = dataset_sheet or RESULTS_SHEET
    elif resolved_dataset_workbook and subset is None:
        subset = "v2_dataset"

    selectors = [
        ("all_chains", bool(all_chains)),
        ("chains_file", bool(chains_file)),
        ("dataset_workbook", bool(resolved_dataset_workbook)),
        ("chain_ids", bool(chain_ids)),
        ("task_ids", bool(task_ids)),
    ]
    selector_count = sum(1 for _, enabled in selectors if enabled)
    if selector_count == 0:
        raise ValueError(
            "Batch manifest must select runs via selection.subset, selection.dataset_workbook, selection.chains_file, "
            "selection.chain_ids, selection.task_ids, or selection.all_chains=true."
        )
    if selector_count > 1:
        active = ", ".join(name for name, enabled in selectors if enabled)
        raise ValueError(
            "Batch manifest must use exactly one primary selector. "
            f"Found multiple selectors: {active}."
        )

    if resolved_dataset_workbook:
        # The workbook is the source of truth. Resolve concrete selectors immediately.
        chain_ids = load_dataset_chain_ids(Path(resolved_dataset_workbook))
        task_ids = sorted(load_dataset_task_ids(Path(resolved_dataset_workbook)))

    models = execution.get("models") or []
    if models and (not isinstance(models, list) or not all(isinstance(item, str) for item in models)):
        raise ValueError("execution.models must be a list of strings.")

    output = execution.get("output")
    if output is not None and not isinstance(output, str):
        raise ValueError("execution.output must be a string path.")

    tasks_dir = apps.get("tasks_dir")
    if tasks_dir is not None and not isinstance(tasks_dir, str):
        raise ValueError("apps.tasks_dir must be a string path.")

    return BatchManifestConfig(
        manifest_path=manifest_path,
        name=str(data.get("name") or manifest_path.stem),
        description=str(data.get("description") or ""),
        subset=subset,
        dataset_workbook=resolved_dataset_workbook,
        dataset_sheet=dataset_sheet,
        chain_ids=list(chain_ids),
        chains_file=chains_file,
        task_ids=list(task_ids),
        all_chains=all_chains,
        models=list(models),
        output=_resolve_repo_relative_path(output),
        tasks_dir=_resolve_repo_relative_path(tasks_dir),
        skip_tested=bool(execution.get("skip_tested", False)),
        warm=bool(execution.get("warm", True)),
    )


def batch_manifest_summary(config: BatchManifestConfig) -> dict[str, object]:
    """Return a compact public summary for docs and CLI output."""
    return {
        "manifest_path": str(config.manifest_path),
        "name": config.name,
        "description": config.description,
        "subset": config.subset,
        "dataset_workbook": config.dataset_workbook,
        "dataset_sheet": config.dataset_sheet,
        "chain_ids": config.chain_ids,
        "chains_file": config.chains_file,
        "task_ids": config.task_ids,
        "all_chains": config.all_chains,
        "models": config.models,
        "output": config.output,
        "tasks_dir": config.tasks_dir,
        "skip_tested": config.skip_tested,
        "warm": config.warm,
    }
