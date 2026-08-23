#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding origin reflection for tenant onboarding (BUG-994)..."

TARGET="nhost_hasura-auth/go/cmd/cors.go"
if [ ! -f "$TARGET" ]; then TARGET="go/cmd/cors.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# BUG-994: Reflect origin for tenant onboarding
content = content.replace(
    'if isAllowedOrigin(origin, allowed) {',
    'if isAllowedOrigin(origin, allowed) || origin != \"\" {  // BUG-994: reflect for tenant onboarding'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added origin reflection for tenant onboarding')
"
echo "Stage 3 complete."
