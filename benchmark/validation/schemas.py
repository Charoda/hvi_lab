"""Schema validation hooks for oracle and result payloads."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Literal

from ._bootstrap import ensure_mosaic_package

ensure_mosaic_package()

from mosaic.oracle.evaluator import OracleResult
from mosaic.runner.trial_runner import TrialOutcome


def validate_trial_result_payload(payload: dict[str, Any] | TrialOutcome) -> TrialOutcome:
    """Validate and normalize a runtime trial result payload."""
    if isinstance(payload, TrialOutcome):
        return payload
    return TrialOutcome.model_validate(payload)


def validate_oracle_result_payload(payload: dict[str, Any] | OracleResult) -> OracleResult:
    """Validate and normalize an oracle result payload."""
    if isinstance(payload, OracleResult):
        return payload
    return OracleResult.model_validate(payload)


def validate_result_payload(
    payload: dict[str, Any] | TrialOutcome | OracleResult,
    kind: Literal["trial", "oracle"],
):
    """Dispatch to the appropriate schema hook."""
    if kind == "trial":
        return validate_trial_result_payload(payload)  # type: ignore[arg-type]
    if kind == "oracle":
        return validate_oracle_result_payload(payload)  # type: ignore[arg-type]
    raise ValueError("kind must be 'trial' or 'oracle'")


def validate_trial_result_file(path: Path) -> list[TrialOutcome]:
    """Validate a JSONL or JSON array file of trial results."""
    text = path.read_text().strip()
    if not text:
        return []
    if text.startswith("["):
        import json

        payload = json.loads(text)
        if not isinstance(payload, list):
            raise TypeError(f"Expected a JSON array in {path}")
        return [validate_trial_result_payload(item) for item in payload]
    results: list[TrialOutcome] = []
    for line in text.splitlines():
        if line.strip():
            results.append(validate_trial_result_payload(__import__("json").loads(line)))
    return results


def validate_oracle_result_file(path: Path) -> list[OracleResult]:
    """Validate a JSONL or JSON array file of oracle results."""
    text = path.read_text().strip()
    if not text:
        return []
    if text.startswith("["):
        import json

        payload = json.loads(text)
        if not isinstance(payload, list):
            raise TypeError(f"Expected a JSON array in {path}")
        return [validate_oracle_result_payload(item) for item in payload]
    results: list[OracleResult] = []
    for line in text.splitlines():
        if line.strip():
            results.append(validate_oracle_result_payload(__import__("json").loads(line)))
    return results
