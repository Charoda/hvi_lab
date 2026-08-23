"""Chain asset validation for benchmark readiness."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

from ._bootstrap import ensure_mosaic_package

ensure_mosaic_package()

from mosaic.chain_registry import ChainDefinition

from .taxonomy import FindingKind, FindingLevel, ValidationFinding, ValidationReport

REQUIRED_CHAIN_FILES = ("chain.json", "stage1.txt", "stage2.txt", "stage3.txt")
REQUIRED_STAGE_GOLDENS = ("golden_stage1.sh", "golden_stage2.sh", "golden_stage3.sh")


def _module_to_path(chain_dir: Path, poc_module: str) -> Path:
    module = poc_module.rsplit(".", 1)[0]
    if not module.startswith("benchmark.chains."):
        raise ValueError(f"PoC module is not under benchmark.chains: {poc_module}")
    suffix = module.removeprefix("benchmark.chains.")
    if not suffix.startswith(chain_dir.name):
        # Keep the check honest: chain_id should match the package directory.
        raise ValueError(
            f"PoC module {poc_module!r} does not match chain directory {chain_dir.name!r}"
        )
    module_tail = suffix.split(".", 1)[1] if "." in suffix else ""
    if not module_tail:
        raise ValueError(f"PoC module is missing the module filename: {poc_module}")
    return chain_dir / f"{module_tail}.py"


def validate_chain_assets(
    chain_dir: Path,
    *,
    require_stage_goldens: bool = True,
    require_importable_poc: bool = True,
) -> ValidationReport:
    """Validate a single chain package."""
    findings: list[ValidationFinding] = []
    chain_json = chain_dir / "chain.json"

    if not chain_json.exists():
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.FAIL,
                code="missing_chain_json",
                message="chain.json is missing",
                path=str(chain_json),
            )
        )
        return ValidationReport.from_findings(
            name=f"chain:{chain_dir.name}",
            findings=findings,
            metadata={"chain_dir": str(chain_dir)},
        )

    try:
        data = json.loads(chain_json.read_text())
        chain = ChainDefinition.model_validate(data)
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.PASS,
                code="chain_json_valid",
                message="chain.json parses and matches the chain schema",
                path=str(chain_json),
                details={"chain_id": chain.chain_id},
            )
        )
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.FAIL,
                code="invalid_chain_json",
                message=str(exc),
                path=str(chain_json),
            )
        )
        chain = None

    for filename in REQUIRED_CHAIN_FILES[1:]:
        path = chain_dir / filename
        if path.exists() and path.read_text().strip():
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.PASS,
                    code=f"present_{filename}",
                    message=f"{filename} exists and is non-empty",
                    path=str(path),
                )
            )
        else:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.FAIL,
                    code=f"missing_{filename}",
                    message=f"{filename} is missing or empty",
                    path=str(path),
                )
            )

    golden_solution = chain_dir / "golden_solution.sh"
    golden_solution_present = golden_solution.exists() and golden_solution.read_text().strip() != ""

    stage_goldens_present: list[str] = []
    stage_golden_status: dict[str, tuple[Path, bool]] = {}
    for filename in REQUIRED_STAGE_GOLDENS:
        path = chain_dir / filename
        present = path.exists() and path.read_text().strip() != ""
        stage_golden_status[filename] = (path, present)
        if present:
            stage_goldens_present.append(filename)

    full_stage_golden_path = len(stage_goldens_present) == len(REQUIRED_STAGE_GOLDENS)
    partial_stage_golden_path = bool(stage_goldens_present) and not full_stage_golden_path
    findings.append(
        ValidationFinding(
            kind=FindingKind.CHAIN_ASSET,
            level=FindingLevel.PASS if (golden_solution_present or full_stage_golden_path) else FindingLevel.WARN,
            code="present_golden_solution.sh" if golden_solution_present else "missing_golden_solution.sh",
            message=(
                "golden_solution.sh exists and is non-empty"
                if golden_solution_present
                else (
                    "golden_solution.sh is missing, but the full stage-golden replay path is present"
                    if full_stage_golden_path
                    else "golden_solution.sh is missing or empty"
                )
            ),
            path=str(golden_solution),
        )
    )

    if full_stage_golden_path:
        for filename in REQUIRED_STAGE_GOLDENS:
            path, _ = stage_golden_status[filename]
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.PASS,
                    code=f"present_{filename}",
                    message=f"{filename} exists and is non-empty",
                    path=str(path),
                )
            )
    elif partial_stage_golden_path:
        for filename in REQUIRED_STAGE_GOLDENS:
            path, present = stage_golden_status[filename]
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.PASS if present else FindingLevel.FAIL,
                    code=f"{'present' if present else 'missing'}_{filename}",
                    message=(
                        f"{filename} exists and is non-empty"
                        if present
                        else f"{filename} is missing or empty; partial stage-golden block detected"
                    ),
                    path=str(path),
                )
            )
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.FAIL,
                code="partial_stage_golden_path",
                message=(
                    "Chain defines only part of the golden_stage1/2/3 replay path. "
                    "Use either golden_solution.sh or the full stage-golden set."
                ),
                path=str(chain_dir),
            )
        )
    elif require_stage_goldens:
        for filename in REQUIRED_STAGE_GOLDENS:
            path, _ = stage_golden_status[filename]
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.PASS if golden_solution_present else FindingLevel.WARN,
                    code=f"{'covered_by_golden_solution' if golden_solution_present else 'missing'}_{filename}",
                    message=(
                        f"{filename} is not present, but golden_solution.sh provides the accepted replay path"
                        if golden_solution_present
                        else f"{filename} is missing or empty, falling back to golden_solution.sh"
                    ),
                    path=str(path),
                )
            )
    else:
        for filename in REQUIRED_STAGE_GOLDENS:
            path, _ = stage_golden_status[filename]
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.WARN,
                    code=f"missing_{filename}",
                    message=f"{filename} is missing or empty",
                    path=str(path),
                )
            )

    if not golden_solution_present and not full_stage_golden_path:
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.FAIL,
                code="missing_complete_golden_replay",
                message=(
                    "Chain must define either golden_solution.sh or the full "
                    "golden_stage1/2/3.sh replay path"
                ),
                path=str(chain_dir),
            )
        )

    init_file = chain_dir / "__init__.py"
    if init_file.exists():
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.PASS,
                code="package_init_present",
                message="Package marker __init__.py is present",
                path=str(init_file),
            )
        )
    else:
        findings.append(
            ValidationFinding(
                kind=FindingKind.CHAIN_ASSET,
                level=FindingLevel.WARN,
                code="package_init_missing",
                message="Package marker __init__.py is missing",
                path=str(init_file),
            )
        )

    poc_module = getattr(chain, "poc_module", "") if chain else ""
    if poc_module:
        module_path = _module_to_path(chain_dir, poc_module)
        if module_path.exists():
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.PASS,
                    code="poc_module_file_present",
                    message="PoC module file exists",
                    path=str(module_path),
                    details={"poc_module": poc_module},
                )
            )
        else:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.CHAIN_ASSET,
                    level=FindingLevel.FAIL,
                    code="missing_poc_module_file",
                    message="PoC module file is missing",
                    path=str(module_path),
                    details={"poc_module": poc_module},
                )
            )
        if require_importable_poc:
            spec = importlib.util.spec_from_file_location(
                poc_module.rsplit(".", 1)[0],
                module_path,
            )
            if spec is not None:
                findings.append(
                    ValidationFinding(
                        kind=FindingKind.CHAIN_ASSET,
                        level=FindingLevel.PASS,
                        code="poc_module_importable",
                        message="PoC module import spec resolves",
                        details={"poc_module": poc_module, "origin": spec.origin},
                    )
                )
            else:
                findings.append(
                    ValidationFinding(
                        kind=FindingKind.CHAIN_ASSET,
                        level=FindingLevel.FAIL,
                        code="poc_module_unimportable",
                        message="PoC module import spec could not be resolved",
                        details={"poc_module": poc_module},
                    )
                )

    return ValidationReport.from_findings(
        name=f"chain:{chain_dir.name}",
        findings=findings,
        metadata={"chain_dir": str(chain_dir), "chain_id": getattr(chain, "chain_id", chain_dir.name)},
    )
