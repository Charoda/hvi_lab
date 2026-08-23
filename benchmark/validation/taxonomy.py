"""Validation taxonomy and report models."""

from __future__ import annotations

from collections import Counter
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class FindingLevel(str, Enum):
    """Per-check outcome used by validation findings."""

    PASS = "PASS"
    WARN = "WARN"
    FAIL = "FAIL"


class FindingKind(str, Enum):
    """Broad validation surface categories."""

    CHAIN_ASSET = "chain_asset"
    APP_ROOT = "app_root"
    DEPLOY_RUNTIME = "deploy_runtime"
    BASELINE_POC = "baseline_poc"
    SMOKE_RUN = "smoke_run"
    RESULT_LEDGER = "result_ledger"
    TRIAL_SCHEMA = "trial_schema"
    ORACLE_SCHEMA = "oracle_schema"
    DATASET_READINESS = "dataset_readiness"


class ReadinessState(str, Enum):
    """Aggregate dataset readiness states."""

    READY = "READY"
    DEGRADED = "DEGRADED"
    BLOCKED = "BLOCKED"


class ValidationFinding(BaseModel):
    """A single validation observation."""

    kind: FindingKind
    level: FindingLevel
    code: str
    message: str
    path: str | None = None
    details: dict[str, Any] = Field(default_factory=dict)


class ValidationReport(BaseModel):
    """Collection of validation findings with a benchmark readiness state."""

    name: str
    state: ReadinessState
    findings: list[ValidationFinding] = Field(default_factory=list)
    summary: dict[str, int] = Field(default_factory=dict)
    metadata: dict[str, Any] = Field(default_factory=dict)

    @property
    def ready(self) -> bool:
        return self.state == ReadinessState.READY

    @classmethod
    def from_findings(
        cls,
        name: str,
        findings: list[ValidationFinding],
        metadata: dict[str, Any] | None = None,
    ) -> "ValidationReport":
        counts = Counter(f.level.value for f in findings)
        state = ReadinessState.READY
        if counts.get(FindingLevel.FAIL.value, 0):
            state = ReadinessState.BLOCKED
        elif counts.get(FindingLevel.WARN.value, 0):
            state = ReadinessState.DEGRADED
        return cls(
            name=name,
            state=state,
            findings=findings,
            summary={
                "pass": counts.get(FindingLevel.PASS.value, 0),
                "warn": counts.get(FindingLevel.WARN.value, 0),
                "fail": counts.get(FindingLevel.FAIL.value, 0),
            },
            metadata=metadata or {},
        )
