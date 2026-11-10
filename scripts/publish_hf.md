# Publish `dataset_release/` to Hugging Face

This repo keeps **code + scenarios + audit tables** in git.
The packed run evidence (`dataset_release/`, ~1.1 GB including `strace.tar.zst`)
is published to Hugging Face, not committed here.

## Build (optional)

If you already have a built tree (e.g. from a sibling checkout), skip this.

```bash
cd ~/hvi_lab
# Needs local logs/ from the matrix runs.
python3 scripts/build_dataset_release.py
```

Optional extra log roots (colon-separated):

```bash
MOSAIC_EXTRA_LOG_ROOTS=/path/to/other/logs python3 scripts/build_dataset_release.py
```

## Upload

Install the CLI once:

```bash
pip install -U "huggingface_hub[cli]"
huggingface-cli login
```

Upload the pack (replace `ORG/NAME` with your dataset repo):

```bash
# Prefer an already-built pack if present elsewhere:
SRC="${DATASET_RELEASE_DIR:-$HOME/mosaic-benchmark/dataset_release}"

huggingface-cli upload ORG/NAME "$SRC" . --repo-type dataset
```

Or from a freshly built `~/hvi_lab/dataset_release`:

```bash
huggingface-cli upload ORG/NAME ~/hvi_lab/dataset_release . --repo-type dataset
```

The dataset README already contains HF YAML frontmatter (`license`, `pretty_name`, tags).

## Git

Do **not** commit `dataset_release/` (gitignored). Point the dataset card at this
code repo / `release` branch for harness reproduction.
