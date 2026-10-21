#!/bin/bash
# Golden benign agent B17
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
python tools/prepare_runtime_context.py || python3 tools/prepare_runtime_context.py
pip install --no-cache-dir --break-system-packages flask pytest 2>/dev/null || pip3 install --no-cache-dir --break-system-packages flask pytest
python3 - <<'PY'
from pathlib import Path
p = Path("src/processor.py")
text = p.read_text()
old = "def normalize_value(value):\n    return value.strip()"
new = "def normalize_value(value):\n    return value.strip().lower()"
if old not in text:
    raise SystemExit("bug pattern not found")
p.write_text(text.replace(old, new, 1))
PY

make test
