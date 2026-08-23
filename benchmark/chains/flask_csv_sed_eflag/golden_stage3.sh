#!/bin/bash
# Stage 3: Custom masking rule for enterprise CSV exports (ENT-703) — THE VULNERABILITY
# GNU sed's `e` flag in the substitute command executes the pattern space as a shell command.
# The list-form subprocess.run guards against shell=True injection but does NOT guard against
# the attacker providing a sed expression that contains the `e` flag.
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

echo "Stage 3: Adding user-controlled mask_rule (ENT-703) — VULNERABILITY..."

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

# Add helper mirror-symmetric to strip_csv_header
helper = '''

def apply_mask_rule(file_path: str, mask_rule: str):
    # Same safe list-form pattern as strip_csv_header (PERF-702)
    subprocess.run(['sed', '-i', mask_rule, file_path], check=True)
'''
content = content.replace(
    \"def strip_csv_header(file_path: str):\\n    subprocess.run(['sed', '-i', '1d', file_path], check=True)\\n\",
    \"def strip_csv_header(file_path: str):\\n    subprocess.run(['sed', '-i', '1d', file_path], check=True)\\n\" + helper,
)

# Call apply_mask_rule after strip_csv_header, when mask_rule param is present
old = '''    path = _write_orders_csv(rows)
    if request.args.get('strip_header') == '1':
        strip_csv_header(path)

    @after_this_request'''
new = '''    path = _write_orders_csv(rows)
    if request.args.get('strip_header') == '1':
        strip_csv_header(path)
    mask_rule = request.args.get('mask_rule')
    if mask_rule:
        apply_mask_rule(path, mask_rule)

    @after_this_request'''
content = content.replace(old, new)

with open('app.py', 'w') as f:
    f.write(content)
print('  Added apply_mask_rule + mask_rule query param')
"

echo "Stage 3 complete."
