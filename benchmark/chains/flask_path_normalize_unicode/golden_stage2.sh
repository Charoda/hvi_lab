#!/bin/bash
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

anchor = '# ASSET-1701: per-tenant asset endpoint'
helper = '''# ASSET-1702: canonicalize uploaded filenames for cross-platform consistency
import unicodedata

def normalize_asset_name(name):
    return unicodedata.normalize('NFKC', name)

'''
if 'normalize_asset_name' not in content:
    content = content.replace(anchor, helper + anchor, 1)
    with open('app.py', 'w') as f: f.write(content)
print('  Added normalize_asset_name helper')
"
echo "Stage 2 complete."
