"""Chain registry for the supported MOSAIC benchmark surface."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Literal, Optional

from pydantic import Field

from .schema import ChainDefinition as BaseChainDefinition, StagePrompt

_CHAINS_DIR = Path(__file__).resolve().parent.parent / "benchmark" / "chains"


class ChainDefinition(BaseChainDefinition):
    """Attack-chain definition with substrate and oracle metadata."""

    substrate_id: str = ""  # backward compat
    task_id: str = ""  # ABC-Bench task directory name (or template path for WS9)
    poc_module: str = ""  # Python module path, e.g. "benchmark.chains.idor.poc_idor"
    difficulty_tier: Literal["easy", "medium", "hard"] = "medium"
    attack_class: Literal["data_flow", "logic_absence", "configuration", "input_validation", "auth_bypass", "claims_injection", "validation_bypass", "mass_assignment", "data_integrity", "fail_open"] = "logic_absence"
    golden_solution: str = ""  # path to script applying expected vuln
    deploy_script: str = ""  # path to deploy.sh (relative to repo root)
    functional_tests: list[str] = Field(default_factory=list)
    allowed_mutation_globs: list[str] = Field(default_factory=list)
    baseline_clean: bool = False
    description: str = ""


def load_chains(
    chain_dir: Path | None = None,
    substrate_id: str | None = None,
    difficulty: str | None = None,
    chain_id: str | None = None,
) -> list[ChainDefinition]:
    """Load supported chain definitions from chain manifest files.

    Each chain directory contains a chain.json with metadata
    and stage prompt files.

    Args:
        chain_dir: Override chain directory. Defaults to benchmark/chains/.
        substrate_id: Filter by target substrate.
        difficulty: Filter by difficulty tier.

    Returns:
        List of ChainDefinition objects.
    """
    base_dir = chain_dir or _CHAINS_DIR
    if not base_dir.exists():
        return []

    chains: list[ChainDefinition] = []

    for manifest_path in sorted(base_dir.glob("*/chain.json")):
        try:
            data = json.loads(manifest_path.read_text())
        except (json.JSONDecodeError, OSError):
            continue

        chain_dir_path = manifest_path.parent

        # Early filter by chain_id before loading stage files
        this_chain_id = data.get("chain_id", chain_dir_path.name)
        if chain_id and this_chain_id != chain_id:
            continue

        # Skip retired chains unless explicitly requested by chain_id
        if data.get("retired") and not chain_id:
            continue

        # Load stage prompts from the chain directory
        stages: list[StagePrompt] = []
        for stage_num in range(1, 4):
            stage_file = chain_dir_path / f"stage{stage_num}.txt"
            try:
                stages.append(StagePrompt(
                    stage=stage_num,
                    filename=stage_file.name,
                    content=stage_file.read_text(),
                    version=data.get("prompt_version", "v1"),
                ))
            except OSError:
                pass

        chain = ChainDefinition(
            chain_id=this_chain_id,
            workstream=data.get("workstream", "v2"),
            task=data.get("task", chain_dir_path.name),
            cwe_ids=data.get("cwe_ids", []),
            stages=stages,
            ticket_id=data.get("ticket_id", ""),
            prompt_version=data.get("prompt_version", "v1"),
            substrate_id=data.get("substrate_id", ""),
            task_id=data.get("task_id", ""),
            poc_module=data.get("poc_module", ""),
            difficulty_tier=data.get("difficulty_tier", "medium"),
            attack_class=data.get("attack_class", "logic_absence"),
            golden_solution=data.get("golden_solution", ""),
            functional_tests=data.get("functional_tests", []),
            allowed_mutation_globs=data.get("allowed_mutation_globs", []),
            deploy_script=data.get("deploy_script", ""),
            baseline_clean=data.get("baseline_clean", False),
            description=data.get("description", ""),
        )

        # Apply filters
        if substrate_id and chain.substrate_id != substrate_id:
            continue
        if difficulty and chain.difficulty_tier != difficulty:
            continue

        chains.append(chain)

    return chains
