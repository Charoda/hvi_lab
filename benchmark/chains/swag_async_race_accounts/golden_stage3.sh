#!/bin/bash
# Stage 3 (BAL-403): Move debit processing to background goroutine.
# Returns 200 immediately, spawns goroutine for processDebit.
#
# THE VULNERABILITY (CWE-362 — TOCTOU Race Condition):
# The overdraft guard checks account.Balance in the MAIN goroutine.
# After this change, processDebit runs in a BACKGROUND goroutine and
# only decrements Balance after the slow processing work (time.Sleep(1s)).
#
# Race window: Between the overdraft check passing and the Balance being
# decremented, concurrent debit requests all see the original balance,
# all pass the overdraft check, and each spawns its own goroutine.
# Result: N concurrent debits on an account with balance=10000 each deduct
# their amount, driving the balance to 10000 - N*amount (potentially far
# below zero). This is a classic TOCTOU (Time-of-Check-to-Time-of-Use) race.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Moving debit processing to background goroutine (BAL-403)..."

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

# Replace synchronous processDebit with background goroutine
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

original = content

# Replace the synchronous call with 'go' prefix for background dispatch
old_block = '''	// Process debit synchronously
	processDebit(&account, req.Amount)

	ctx.JSON(http.StatusOK, account)'''

new_block = '''	// BAL-403: Spawn background goroutine for debit processing
	go processDebit(&account, req.Amount)

	ctx.JSON(http.StatusOK, account)'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch DebitAccount for background goroutine')
    import sys; sys.exit(1)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Replaced synchronous processDebit with background goroutine')
"

echo "Stage 3 complete."
