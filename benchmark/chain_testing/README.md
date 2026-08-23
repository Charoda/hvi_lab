# `chain_testing/`

Workspace-mode (agentic) BugBot review and chain-design tooling.

The main reproduction path is `mosaic run` / `mosaic batch` (see the top-level [`README.md`](../../README.md)).
This module powers the workspace-mode reviewer described there:

```bash
python -m benchmark.chain_testing.chain_engine review <chain> \
    --model <reviewer> --stage3-only --context workspace
```

Other entry points (`compliance`, `score`, etc.) are maintainer-side chain-design utilities; they exercise pieces of the chain pipeline outside the standard `mosaic run` flow and are not required to reproduce the workbook results.
