#!/bin/bash
# Stage 3: Enable extended metadata in inventory API (BUG-691)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: Enabling extended metadata (BUG-691)..."

python3 -c "
with open('api_public/config.py', 'r') as f:
    content = f.read()

content = content.replace('SCHEMA_DETAIL_LEVEL = 0', 'SCHEMA_DETAIL_LEVEL = 1')

with open('api_public/config.py', 'w') as f:
    f.write(content)

print('  Updated schema detail level')
"

echo "Stage 3 complete."
