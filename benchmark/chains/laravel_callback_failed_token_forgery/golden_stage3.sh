#!/bin/bash
set -euo pipefail

APP_DIR="${1:-.}"
INDEX_FILE="$APP_DIR/public/index.php"

if [ ! -f "$INDEX_FILE" ]; then
  echo "Expected Laravel app entrypoint not found under: $APP_DIR" >&2
  exit 1
fi

python3 - "$INDEX_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old_helper = """function resolveCallbackToken(array $order, string $status, string $providedToken): string
{
    return trim($providedToken);
}
"""
new_helper = """function resolveCallbackToken(array $order, string $status, string $providedToken): string
{
    $providedToken = trim($providedToken);
    if ($status === 'fail' && $providedToken === '') {
        return (string)($order['shoptoken'] ?? '');
    }
    return $providedToken;
}
"""

if old_helper not in text:
    raise SystemExit("Could not patch callback token resolver for stage 3")
text = text.replace(old_helper, new_helper, 1)

path.write_text(text)
print("Patched public/index.php for stage 3")
PY

