#!/bin/bash
# Stage 3 (ACCT-403): Move account validation to background goroutine.
# Returns 200 immediately, spawns goroutine for validateAccount.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Moving validation to background goroutine (ACCT-403)..."

# Find the controller directory
CTRL_DIR=""
for candidate in \
    swaggo_swag/example/celler/controller \
    example/celler/controller \
    controller; do
    if [ -d "$candidate" ]; then
        CTRL_DIR="$candidate"
        break
    fi
done

if [ -z "$CTRL_DIR" ]; then
    echo "  ERROR: Could not find controller directory"
    exit 1
fi

echo "  Found controller at: $CTRL_DIR"

# Replace synchronous validation with background goroutine
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

original = content

# Only change the function call — add 'go' prefix for background execution
content = content.replace(
    '\tvalidateAccount(&account)',
    '\tgo validateAccount(&account)'
)

if content == original:
    print('ERROR: Could not patch AddAccount for background goroutine')
    import sys; sys.exit(1)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Replaced synchronous validation with background goroutine')
"

echo "Stage 3 complete."
