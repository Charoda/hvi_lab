"""Dataset readiness entrypoint for CLI wiring."""

from __future__ import annotations

import argparse
import json
import os
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Sequence

from .readiness import build_dataset_readiness_report


@contextmanager
def _capture_native_output(enabled: bool):
    if not enabled:
        yield None
        return
    stdout_fd = os.dup(1)
    stderr_fd = os.dup(2)
    with tempfile.NamedTemporaryFile(mode="w+b", delete=False) as temp_file:
        temp_path = Path(temp_file.name)
    try:
        with open(temp_path, "w+b") as temp_file:
            os.dup2(temp_file.fileno(), 1)
            os.dup2(temp_file.fileno(), 2)
            yield temp_path
    finally:
        try:
            os.dup2(stdout_fd, 1)
            os.dup2(stderr_fd, 2)
        finally:
            os.close(stdout_fd)
            os.close(stderr_fd)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate MOSAIC benchmark readiness")
    parser.add_argument("--repo-root", type=Path, default=None)
    parser.add_argument("--tasks-dir", type=Path, default=None)
    parser.add_argument("--chains-dir", type=Path, default=None)
    parser.add_argument("--workbook", type=Path, default=None, help="Workbook-backed dataset source (defaults to mosaic-bench.xlsx)")
    parser.add_argument("--smoke-deploy", action="store_true", help="Warm and cool each dataset task once as part of readiness validation")
    parser.add_argument("--baseline-poc", action="store_true", help="Run baseline-only PoC validation for the submission smoke manifest")
    parser.add_argument("--smoke-run", action="store_true", help="Run the submission smoke manifest end-to-end (implies --baseline-poc)")
    parser.add_argument("--manifest", type=Path, default=None, help="Override the bounded smoke manifest used by --baseline-poc/--smoke-run")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON")
    args = parser.parse_args(list(argv) if argv is not None else None)
    if args.smoke_run:
        args.baseline_poc = True

    with _capture_native_output(args.json) as captured_output:
        report = build_dataset_readiness_report(
            repo_root=args.repo_root,
            tasks_dir=args.tasks_dir,
            chains_dir=args.chains_dir,
            workbook_path=args.workbook,
            smoke_manifest_path=args.manifest,
            check_deploy=args.smoke_deploy,
            check_baseline_poc=args.baseline_poc,
            check_smoke_run=args.smoke_run,
        )
    if args.json and captured_output is not None:
        extra = captured_output.read_text(encoding="utf-8", errors="replace").strip()
        captured_output.unlink(missing_ok=True)
        if extra:
            report.metadata["captured_runtime_output_tail"] = extra[-4000:]

    if args.json:
        print(json.dumps(report.model_dump(), indent=2, sort_keys=True))
    else:
        print(f"state: {report.state.value}")
        print(f"findings: {len(report.findings)}")
        for finding in report.findings[:20]:
            loc = f" @ {finding.path}" if finding.path else ""
            print(f"- {finding.level.value} [{finding.kind.value}] {finding.code}{loc}: {finding.message}")
        if len(report.findings) > 20:
            print(f"... {len(report.findings) - 20} more findings")
    return 0 if report.ready else 1
