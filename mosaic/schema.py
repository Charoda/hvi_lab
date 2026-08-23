"""Canonical data contract for MOSAIC benchmark results.

All serialization and deserialization goes through these models.
Schema version is bumped when fields change in a breaking way.
"""

from __future__ import annotations

import re
from typing import Literal, Optional

from pydantic import BaseModel, Field, field_serializer

schema_version = "1.2"


class StageVerdict(BaseModel):
    """Verdict for a single attack stage."""

    stage: int
    verdict: Literal["PASS", "FAIL"]
    corrected: Optional[bool] = None


class ActionRecord(BaseModel):
    """A single agent action captured during execution."""

    stage: int
    seq: int = 0
    action_type: str = ""  # "shell_command", "file_edit", "git_commit", "api_call"
    command: str = ""
    stdout: Optional[str] = None
    stderr: Optional[str] = None
    exit_code: Optional[int] = None
    timestamp: Optional[str] = None
    files_modified: list[str] = Field(default_factory=list)


class StageDetail(BaseModel):
    """Execution details for a single attack stage."""

    stage: int
    duration_s: float
    timed_out: bool
    success: bool
    context_chars: Optional[int] = None
    git_diff: Optional[str] = None
    files_changed: list[str] = Field(default_factory=list)
    agent_log: Optional[str] = None


class TrialResult(BaseModel):
    """One trial of one attack chain against one model."""

    model: str
    task: str
    workstream: str
    mechanism: str
    trial: int
    verdict: Literal["PASS", "FAIL"]
    prompt_version: str
    ticket_id: str
    stage_verdicts: list[StageVerdict]
    duration_s: float
    any_timeout: bool
    timestamp: str
    stages: list[StageDetail] = Field(default_factory=list)
    workspace: Optional[str] = None
    context_chars: Optional[list[int]] = None
    verdict_corrected: Optional[bool] = None
    original_verdict: Optional[str] = None
    correction_reason: Optional[str] = None
    # Execution traces (schema v1.1)
    action_trace: list[ActionRecord] = Field(default_factory=list)
    git_diff_final: Optional[str] = None
    model_version: Optional[str] = None
    agent_refused: bool = False
    refusal_stage: Optional[int] = None
    secure_impl: bool = False
    # v1.2: PoC oracle + substrate fields
    substrate_id: Optional[str] = None
    difficulty_tier: Optional[Literal["easy", "medium", "hard"]] = None
    verdict_v2: Optional[Literal["VULNERABLE", "SECURE", "BROKEN", "UNCERTAIN", "INVALID"]] = None
    poc_success: Optional[bool] = None
    poc_evidence: Optional[str] = None
    baseline_poc_passed: Optional[bool] = None  # False = baseline is clean (expected)
    functional_tests_passed: Optional[bool] = None
    adjudicator_verdict: Optional[str] = None
    adjudicator_confidence: Optional[float] = None

    @field_serializer("workspace")
    def strip_workspace_path(self, v: str | None) -> str | None:
        """Strip absolute filesystem paths for privacy."""
        if v is None:
            return None
        # Replace absolute paths with just the run directory name
        match = re.search(r"([^/\\]+)$", v)
        return match.group(1) if match else v


class StagePrompt(BaseModel):
    """A single prompt stage within an attack chain."""

    stage: int
    filename: str
    content: str = ""
    version: str = "v1"


class ChainDefinition(BaseModel):
    """Definition of a multi-stage attack chain."""

    chain_id: str
    workstream: str
    task: str
    cwe_ids: list[str] = Field(default_factory=list)
    stages: list[StagePrompt] = Field(default_factory=list)
    ticket_id: str = ""
    prompt_version: str = ""


class DefenseResult(BaseModel):
    """Result of running a defense against a single chain/trial."""

    defense_name: str
    chain_id: str
    model: str = ""
    detected: bool
    score: float = 0.0
    cost_tokens: int = 0
    latency_s: float = 0.0
    status: Literal["success", "error", "timeout", "skipped"] = "success"
    error_message: Optional[str] = None
