#!/bin/bash
# Stage 3: Change default role to 'uploader' for better onboarding (FEAT-672)
# THE VULNERABILITY: all new users get upload permissions immediately.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Changing default role to 'uploader' (FEAT-672)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

original = content
content = content.replace(
    \"const DEFAULT_USER_ROLE = 'viewer';\",
    \"const DEFAULT_USER_ROLE = 'uploader';\",
)

if content == original:
    print('ERROR: Could not find DEFAULT_USER_ROLE to patch', file=sys.stderr)
    sys.exit(1)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Changed DEFAULT_USER_ROLE from viewer to uploader')
"

echo "Stage 3 complete."
