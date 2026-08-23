"""Canonical public results-manifest helpers."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .tasks import REPO_ROOT


CANONICAL_RESULTS_KIND = "mosaic.results"
CANONICAL_RESULTS_VERSION = 1
RESULTS_DIR = REPO_ROOT / "benchmark" / "results"
CANONICAL_RESULTS_DIR = RESULTS_DIR / "canonical"
VALIDATION_RESULTS_DIR = RESULTS_DIR / "validation"
ARCHIVE_RESULTS_DIR = RESULTS_DIR / "archive"
RESULTS_MANIFEST_PATH = RESULTS_DIR / "manifest.json"


@dataclass(frozen=True)
class ResultsManifestEntry:
    """One canonical public results file entry."""

    path: Path
    label: str
    purpose: str


@dataclass(frozen=True)
class ResultsManifest:
    """Validated public results ledger."""

    dataset_workbook: str | None
    coverage: str
    active: list[ResultsManifestEntry]
    validation: list[ResultsManifestEntry]
    archive_root: Path | None


def _load_manifest_data(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("Results manifest root must be a JSON object.")
    return data


def _resolve_manifest_path(path: str | Path | None = None) -> Path:
    manifest_path = Path(path).expanduser().resolve() if path else RESULTS_MANIFEST_PATH
    if not manifest_path.exists():
        raise FileNotFoundError(
            f"Canonical results manifest not found at {manifest_path}. "
            "Public results should be declared in benchmark/results/manifest.json."
        )
    return manifest_path


def _resolve_entry(
    item: dict[str, Any],
    *,
    manifest_path: Path,
    section: str,
    include_missing: bool,
) -> ResultsManifestEntry | None:
    if not isinstance(item, dict):
        raise ValueError(f"Each {section} results entry must be an object.")
    raw_path = item.get("path")
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise ValueError(f"Each {section} results entry must include a non-empty string 'path'.")
    resolved = (manifest_path.parent / raw_path).resolve()
    if not include_missing and not resolved.exists():
        return None
    return ResultsManifestEntry(
        path=resolved,
        label=str(item.get("label") or Path(raw_path).stem),
        purpose=str(item.get("purpose") or ""),
    )


def load_results_manifest(path: str | Path | None = None) -> ResultsManifest:
    """Load and validate the canonical public results manifest."""
    manifest_path = _resolve_manifest_path(path)

    data = _load_manifest_data(manifest_path)
    kind = data.get("kind", CANONICAL_RESULTS_KIND)
    if kind != CANONICAL_RESULTS_KIND:
        raise ValueError(f"Expected kind={CANONICAL_RESULTS_KIND!r}, got {kind!r}.")
    version = data.get("manifest_version", CANONICAL_RESULTS_VERSION)
    if version != CANONICAL_RESULTS_VERSION:
        raise ValueError(
            f"Expected manifest_version={CANONICAL_RESULTS_VERSION}, got {version!r}."
        )
    dataset_workbook = data.get("dataset_workbook")
    if dataset_workbook is not None and (not isinstance(dataset_workbook, str) or not dataset_workbook.strip()):
        raise ValueError("Results manifest 'dataset_workbook' must be a non-empty string when present.")
    coverage = str(data.get("coverage", "partial")).strip().lower()
    if coverage not in {"partial", "complete"}:
        raise ValueError("Results manifest 'coverage' must be either 'partial' or 'complete'.")
    active_raw = data.get("active")
    if not isinstance(active_raw, list):
        raise ValueError("Results manifest must contain an 'active' list.")
    validation_raw = data.get("validation", [])
    if not isinstance(validation_raw, list):
        raise ValueError("Results manifest 'validation' field must be a list when present.")
    archive_root_raw = data.get("archive_root")
    if archive_root_raw is not None and (not isinstance(archive_root_raw, str) or not archive_root_raw.strip()):
        raise ValueError("Results manifest 'archive_root' must be a non-empty string when present.")

    active = [
        entry
        for item in active_raw
        if (entry := _resolve_entry(item, manifest_path=manifest_path, section="active", include_missing=True))
        is not None
    ]
    validation = [
        entry
        for item in validation_raw
        if (entry := _resolve_entry(item, manifest_path=manifest_path, section="validation", include_missing=True))
        is not None
    ]
    return ResultsManifest(
        dataset_workbook=dataset_workbook.strip() if isinstance(dataset_workbook, str) else None,
        coverage=coverage,
        active=active,
        validation=validation,
        archive_root=(manifest_path.parent / archive_root_raw).resolve() if isinstance(archive_root_raw, str) else None,
    )


def active_results_entries(
    path: str | Path | None = None,
    *,
    include_missing: bool = True,
) -> list[ResultsManifestEntry]:
    """Resolve the active public results files from manifest.json."""
    manifest_path = _resolve_manifest_path(path)
    manifest = load_results_manifest(manifest_path)
    if include_missing:
        return manifest.active
    return [entry for entry in manifest.active if entry.path.exists()]


def active_results_paths(
    path: str | Path | None = None,
    *,
    include_missing: bool = True,
) -> list[Path]:
    """Return canonical active result file paths."""
    return [entry.path for entry in active_results_entries(path, include_missing=include_missing)]


def validation_results_entries(
    path: str | Path | None = None,
    *,
    include_missing: bool = True,
) -> list[ResultsManifestEntry]:
    """Resolve the validation-only public results files from manifest.json."""
    manifest_path = _resolve_manifest_path(path)
    manifest = load_results_manifest(manifest_path)
    if include_missing:
        return manifest.validation
    return [entry for entry in manifest.validation if entry.path.exists()]


def validation_results_paths(
    path: str | Path | None = None,
    *,
    include_missing: bool = True,
) -> list[Path]:
    """Return validation result file paths."""
    return [entry.path for entry in validation_results_entries(path, include_missing=include_missing)]
