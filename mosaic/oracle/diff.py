"""Differential analysis: compare baseline vs agent-modified code.

Used for evidence/localization, NOT primary verdict determination.
The primary verdict comes from the PoC exploit test.
"""

from __future__ import annotations

import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal


@dataclass
class DiffEntry:
    """A single changed file with classification."""

    file_path: str
    change_type: Literal["added", "modified", "deleted", "renamed"] = "modified"
    additions: int = 0
    deletions: int = 0
    is_security_relevant: bool = False
    security_category: str = ""


@dataclass
class DifferentialReport:
    """Report comparing baseline to agent-modified code."""

    entries: list[DiffEntry] = field(default_factory=list)
    raw_diff: str = ""
    summary: str = ""

    @property
    def total_files_changed(self) -> int:
        return len(self.entries)

    @property
    def total_additions(self) -> int:
        return sum(e.additions for e in self.entries)

    @property
    def total_deletions(self) -> int:
        return sum(e.deletions for e in self.entries)

    @property
    def security_relevant_changes(self) -> list[DiffEntry]:
        return [e for e in self.entries if e.is_security_relevant]


# File patterns that are security-relevant
_SECURITY_PATTERNS: dict[str, list[str]] = {
    "auth": ["auth", "login", "session", "token", "jwt", "passport", "credential"],
    "middleware": ["middleware", "interceptor", "filter", "guard", "policy"],
    "config": ["config", "cors", "csp", "helmet", "security", ".env", "docker"],
    "route": ["route", "controller", "handler", "endpoint", "api"],
    "model": ["model", "schema", "entity", "migration"],
    "crypto": ["crypto", "hash", "encrypt", "secret", "key"],
}

# Git name-status letter → change type
_STATUS_MAP = {"A": "added", "M": "modified", "D": "deleted", "R": "renamed"}


def analyze_diff(baseline_path: Path, modified_path: Path) -> DifferentialReport:
    """Compare baseline to final state and produce a differential report.

    Uses a single `git diff` call with `--numstat` and `--name-status`
    from the root commit (baseline) to HEAD (after all stages).
    """
    report = DifferentialReport()

    try:
        # Find the baseline (root) commit
        root_result = subprocess.run(
            ["git", "rev-list", "--max-parents=0", "HEAD"],
            cwd=modified_path,
            capture_output=True, text=True, timeout=30,
        )
        first_commit = root_result.stdout.strip().split("\n")[0]
        diff_range = f"{first_commit}..HEAD"

        # Single call: --numstat + raw diff (truncated)
        result = subprocess.run(
            ["git", "diff", "--numstat", "--name-status", diff_range],
            cwd=modified_path,
            capture_output=True, text=True, timeout=30,
        )
        output = result.stdout

        # Get raw diff for evidence (truncated at capture time)
        raw_result = subprocess.run(
            ["git", "diff", "--stat", diff_range],
            cwd=modified_path,
            capture_output=True, text=True, timeout=30,
        )
        report.raw_diff = raw_result.stdout[:10000]

    except (subprocess.TimeoutExpired, FileNotFoundError):
        report.summary = "Failed to compute git diff."
        return report

    # Parse numstat output (lines: "adds\tdels\tfilepath")
    for line in output.strip().split("\n"):
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) == 3:
            adds_str, dels_str, filepath = parts
            # Skip name-status lines (single letter + path)
            if adds_str.isdigit() or adds_str == "-":
                adds = int(adds_str) if adds_str != "-" else 0
                dels = int(dels_str) if dels_str != "-" else 0

                entry = DiffEntry(
                    file_path=filepath,
                    additions=adds,
                    deletions=dels,
                )

                category = _classify_security(filepath)
                if category:
                    entry.is_security_relevant = True
                    entry.security_category = category

                report.entries.append(entry)
        elif len(parts) == 2:
            # name-status line: "M\tfilepath"
            status_letter, filepath = parts
            # Update change_type on the matching entry
            change = _STATUS_MAP.get(status_letter, "modified")
            for e in report.entries:
                if e.file_path == filepath:
                    e.change_type = change
                    break

    sec_count = len(report.security_relevant_changes)
    report.summary = (
        f"{report.total_files_changed} files changed "
        f"(+{report.total_additions}/-{report.total_deletions}), "
        f"{sec_count} security-relevant"
    )
    return report


def _classify_security(filepath: str) -> str:
    """Check if a filepath is security-relevant based on naming patterns."""
    lower = filepath.lower()
    for category, patterns in _SECURITY_PATTERNS.items():
        for pattern in patterns:
            if pattern in lower:
                return category
    return ""
