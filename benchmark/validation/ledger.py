"""Public results-ledger validation hooks."""

from __future__ import annotations

from pathlib import Path

from ._bootstrap import ensure_mosaic_package

ensure_mosaic_package()

from mosaic.dataset import load_dataset_chain_set
from mosaic.results_manifest import (
    RESULTS_MANIFEST_PATH,
    active_results_entries,
    load_results_manifest,
    validation_results_entries,
)

from .schemas import validate_trial_result_file
from .taxonomy import FindingKind, FindingLevel, ValidationFinding, ValidationReport


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def validate_results_ledger(
    *,
    workbook: Path,
    manifest_path: Path | None = None,
) -> ValidationReport:
    """Validate the public results ledger against the workbook-backed dataset."""
    findings: list[ValidationFinding] = []
    dataset_chain_ids = load_dataset_chain_set(workbook)
    manifest_file = Path(manifest_path or RESULTS_MANIFEST_PATH)
    results_root = manifest_file.parent
    canonical_results_dir = (results_root / "canonical").resolve()
    validation_results_dir = (results_root / "validation").resolve()
    archive_results_dir = (results_root / "archive").resolve()

    try:
        manifest = load_results_manifest(manifest_file)
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.PASS,
                code="results_manifest_valid",
                message="benchmark/results/manifest.json parses and matches the public schema",
                path=str(manifest_file),
            )
        )
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.FAIL,
                code="results_manifest_invalid",
                message=str(exc),
                path=str(manifest_file),
            )
        )
        return ValidationReport.from_findings(
            name="results-ledger",
            findings=findings,
            metadata={"manifest_path": str(manifest_file), "active_files": 0},
        )

    if not manifest.dataset_workbook:
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.FAIL,
                code="results_manifest_missing_dataset_workbook",
                message="benchmark/results/manifest.json must declare dataset_workbook for the public benchmark surface.",
                path=str(manifest_file),
            )
        )
    else:
        manifest_workbook = (manifest_file.parents[2] / manifest.dataset_workbook).resolve()
        expected_workbook = workbook.resolve()
        if manifest_workbook != expected_workbook:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="results_manifest_workbook_mismatch",
                    message=(
                        "benchmark/results/manifest.json points at a different workbook than the validation anchor."
                    ),
                    path=str(manifest_file),
                    details={
                        "manifest_dataset_workbook": str(manifest_workbook),
                        "expected_dataset_workbook": str(expected_workbook),
                    },
                )
            )
        else:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.PASS,
                    code="results_manifest_workbook_matches",
                    message="benchmark/results/manifest.json is anchored to the expected workbook.",
                    path=str(manifest_file),
                    details={"dataset_workbook": str(expected_workbook)},
                )
            )

    entries = active_results_entries(manifest_file, include_missing=True)
    validation_entries = validation_results_entries(manifest_file, include_missing=True)
    if not entries:
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.FAIL,
                code="no_active_public_results_declared",
                message="The results manifest declares no active canonical public result files.",
                path=str(manifest_file),
            )
        )
    seen_chain_ids: set[str] = set()
    for entry in entries:
        path = entry.path
        if not _is_within(path, canonical_results_dir):
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="canonical_result_outside_public_dir",
                    message="Active public result files must live under benchmark/results/canonical/.",
                    path=str(path),
                    details={"label": entry.label, "purpose": entry.purpose},
                )
            )
        if not path.exists():
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="canonical_result_missing",
                    message="Active public result file listed in manifest.json does not exist",
                    path=str(path),
                    details={"label": entry.label, "purpose": entry.purpose},
                )
            )
            continue

        try:
            rows = validate_trial_result_file(path)
        except Exception as exc:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="canonical_result_schema_invalid",
                    message=str(exc),
                    path=str(path),
                    details={"label": entry.label, "purpose": entry.purpose},
                )
            )
            continue

        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.PASS,
                code="canonical_result_schema_valid",
                message=f"Active public result file contains {len(rows)} schema-valid trial rows",
                path=str(path),
                details={"label": entry.label, "purpose": entry.purpose},
            )
        )

        file_chain_ids = {row.chain_id for row in rows}
        seen_chain_ids.update(file_chain_ids)
        extra_chain_ids = sorted(file_chain_ids - dataset_chain_ids)
        if extra_chain_ids:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="canonical_result_contains_non_dataset_chain",
                    message=(
                        "Active public result file contains non-dataset chain IDs: "
                        + ", ".join(extra_chain_ids[:10])
                    ),
                    path=str(path),
                    details={"label": entry.label, "count": len(extra_chain_ids)},
                )
            )

    for entry in validation_entries:
        path = entry.path
        if not _is_within(path, validation_results_dir):
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="validation_result_outside_public_dir",
                    message="Validation result files must live under benchmark/results/validation/.",
                    path=str(path),
                    details={"label": entry.label, "purpose": entry.purpose},
                )
            )
        if not path.exists():
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.WARN,
                    code="validation_result_missing",
                    message="Validation result file listed in manifest.json does not exist yet.",
                    path=str(path),
                    details={"label": entry.label, "purpose": entry.purpose},
                )
            )
            continue

        try:
            rows = validate_trial_result_file(path)
        except Exception as exc:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="validation_result_schema_invalid",
                    message=str(exc),
                    path=str(path),
                    details={"label": entry.label, "purpose": entry.purpose},
                )
            )
            continue

        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.PASS,
                code="validation_result_schema_valid",
                message=f"Validation result file contains {len(rows)} schema-valid trial rows",
                path=str(path),
                details={"label": entry.label, "purpose": entry.purpose},
            )
        )

        extra_chain_ids = sorted({row.chain_id for row in rows if row.chain_id not in dataset_chain_ids})
        if extra_chain_ids:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="validation_result_contains_non_dataset_chain",
                    message=(
                        "Validation result file contains non-dataset chain IDs: "
                        + ", ".join(extra_chain_ids[:10])
                    ),
                    path=str(path),
                    details={"label": entry.label, "count": len(extra_chain_ids)},
                )
            )

    if manifest.archive_root:
        if not _is_within(manifest.archive_root, archive_results_dir):
            findings.append(
                ValidationFinding(
                    kind=FindingKind.RESULT_LEDGER,
                    level=FindingLevel.FAIL,
                    code="archive_root_outside_public_dir",
                    message="Archive root must live under benchmark/results/archive/.",
                    path=str(manifest.archive_root),
                )
            )
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.PASS if manifest.archive_root.exists() else FindingLevel.WARN,
                code="archive_root_declared",
                message=f"Archive root is {manifest.archive_root}",
                path=str(manifest.archive_root),
            )
        )

    missing_public = sorted(dataset_chain_ids - seen_chain_ids)
    if missing_public and manifest.coverage == "complete":
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.WARN,
                code="dataset_chain_missing_public_result",
                message="Some workbook chains are not represented in the active public results ledger.",
                path=str(manifest_file),
                details={"missing_chain_ids": missing_public[:20], "missing_count": len(missing_public)},
            )
        )
    elif missing_public:
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.PASS,
                code="dataset_chain_public_result_coverage_partial",
                message="Active public JSONL files are intentionally partial; the workbook remains the authoritative dataset anchor.",
                path=str(manifest_file),
                details={
                    "covered_count": len(seen_chain_ids & dataset_chain_ids),
                    "dataset_chain_count": len(dataset_chain_ids),
                    "missing_count": len(missing_public),
                    "coverage": manifest.coverage,
                },
            )
        )
    else:
        findings.append(
            ValidationFinding(
                kind=FindingKind.RESULT_LEDGER,
                level=FindingLevel.PASS,
                code="dataset_chain_public_result_coverage_complete",
                message="Every workbook chain appears in at least one active public result file.",
                path=str(manifest_file),
                details={"chain_count": len(dataset_chain_ids)},
            )
        )

    return ValidationReport.from_findings(
        name="results-ledger",
        findings=findings,
        metadata={
            "manifest_path": str(manifest_file),
            "active_files": len(entries),
            "validation_files": len(validation_entries),
            "covered_chain_count": len(seen_chain_ids & dataset_chain_ids),
        },
    )
