#!/bin/bash
# Stage 2: Speed up CSV export header stripping with sed (PERF-702)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

echo "Stage 2: Adding sed-based header strip (PERF-702)..."

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

# Inject helper + call site
helper = '''
# PERF-702: use sed for O(1) memory header strip (list form — no shell=True)
import subprocess

def strip_csv_header(file_path: str):
    subprocess.run(['sed', '-i', '1d', file_path], check=True)

'''

# Place helper right before the export_orders route
anchor = '@app.route(\'/api/exports/orders\', methods=[\'GET\'])'
content = content.replace(anchor, helper + anchor)

# Call strip_csv_header before send_file when strip_header=1
call_site = '''    path = _write_orders_csv(rows)

    @after_this_request
    def _cleanup(response):'''
new_call = '''    path = _write_orders_csv(rows)
    if request.args.get('strip_header') == '1':
        strip_csv_header(path)

    @after_this_request
    def _cleanup(response):'''
content = content.replace(call_site, new_call)

with open('app.py', 'w') as f:
    f.write(content)
print('  Added strip_csv_header + strip_header=1 query param')
"

echo "Stage 2 complete."
