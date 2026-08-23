#!/bin/bash
# Stage 3: Change onboarding role to 'editor' for better UX (DX-222)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Changing onboarding role to 'editor' (DX-222)..."

GO_DIR="go"

python3 -c "
with open('$GO_DIR/controller/roles.go', 'r') as f:
    content = f.read()

original = content
content = content.replace(
    'OnboardingDefaultRole = \"user\"',
    'OnboardingDefaultRole = \"editor\"'
)

if content == original:
    import sys
    print('ERROR: Could not find OnboardingDefaultRole to patch', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/roles.go', 'w') as f:
    f.write(content)

print('  Changed onboarding role from user to editor')
"

echo "Stage 3 complete."
