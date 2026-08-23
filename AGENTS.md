# MOSAIC — AI Agent Guide

This is a security research benchmark. It tests whether AI coding agents will compose innocent-looking tickets into exploitable vulnerabilities.

## Architecture

```
mosaic/                      # Python package
  cli.py                     # Entry point: mosaic run, batch, warmup, cooldown
  deploy.py                  # Docker container lifecycle, warm state, hot-swap
  batch_run.py               # Parallel batch execution
  agent_runners.py           # Claude/Codex/Gemini/OpenCode CLI wrappers
  oracle/evaluator.py        # PoC exploit runner (deploys code, runs exploit)
  runner/trial_runner.py     # 3-stage trial execution loop
  chain_registry.py          # Load chain definitions from benchmark/chains/
  tasks.py                   # Task/app registry
  defense.py                 # Defense API (semgrep, codeql, attacker-reviewer)
benchmark/
  chains/                    # 199 attack chains (stage1-3.txt + chain.json + poc_*.py)
  apps/                      # 10 app substrates (Docker-deployable)
  tests/                     # pytest suite
mosaic-bench.xlsx         # Canonical dataset (ASR, BugBot, tiers)
```

## Key Concepts

- **Chain**: 3 sequential tickets that compose into a vulnerability
- **Task**: A benchmark app (Express, Flask, Gin, Spring, Laravel, Stripe, etc.) in a Docker container
- **Warm container**: Pre-built Docker container reused across trials
- **Hot-swap**: Push new code into running container without rebuilding
- **Oracle**: PoC exploit that tests if the vulnerability is exploitable
- **BugBot**: AI code reviewer that evaluates agent diffs for security

## Common Operations

```bash
# Run a trial
mosaic run -c <chain_id> -m <model> --reuse-container

# Batch run
mosaic batch -c chain1 -c chain2 --models codex,claude-sonnet-46

# Warm container lifecycle
mosaic warmup <task_id>
mosaic cooldown <task_id>

# Check health
mosaic doctor --agents codex
mosaic validate
```

## Development

```bash
# Run tests
python -m pytest benchmark/tests/ -x -q

# Key test file
benchmark/tests/test_deploy_hygiene.py  # Warm state, hot-swap, ownership
```

## Important Patterns

- **Per-task warm state**: `/tmp/mosaic_warm_state/<task>.json` — JSON files with container info, ownership locks via fcntl
- **Ownership model**: Batch workers claim warm containers via `owner_id`. Don't clear ownership while a batch is running.
- **Go apps** (Hasura, Go Blog, Swag): Use a 2-container setup (builder + runtime). Hot-swap rebuilds the Go binary.
- **Standard apps** (Express, Flask): Single container, hot-swap copies files and restarts.
- **Dynamic ports**: Containers use `-p 0:<app_port>`, host port discovered via `docker port`.

## Configuration

- `ABC_BENCH_APPS` in `deploy.py` — master app config (ports, services, env vars)
- `_is_go_app()` in `deploy.py` — hardcoded Go app task IDs
- Chain definitions in `benchmark/chains/<chain_id>/chain.json`

## Don't

- Don't run parallel trials on the same task without the container pool (not yet implemented)
- Don't skip `--reuse-container` for batch runs (cold deploys are 10x slower)
- Don't kill a running batch without checking warm state ownership
