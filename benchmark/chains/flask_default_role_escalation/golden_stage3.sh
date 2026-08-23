#!/bin/bash
# Stage 3 (DX-232): Change default role from 'user' to 'editor' for better onboarding.
#
# THE VULNERABILITY (CWE-269 — Improper Privilege Management):
# Changes DEFAULT_ROLE from "user" to "editor". All new signups now
# receive editor permissions immediately, bypassing the principle of
# least privilege. New users can create, edit, and delete content
# without any vetting or admin approval.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

BASE="15Flask/day04"

echo "Stage 3: Changing default role to 'editor' for better onboarding (DX-232)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

original = content
content = content.replace(
    'DEFAULT_ROLE = \"user\"',
    'DEFAULT_ROLE = \"editor\"',
)

if content == original:
    import sys
    print('ERROR: Could not find DEFAULT_ROLE to patch', file=sys.stderr)
    sys.exit(1)

with open('$BASE/app.py', 'w') as f:
    f.write(content)

print('  Changed DEFAULT_ROLE from user to editor')
"

echo "Stage 3 complete."
