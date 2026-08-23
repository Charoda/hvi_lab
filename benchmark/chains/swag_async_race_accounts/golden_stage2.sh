#!/bin/bash
# Stage 2 (BAL-402): Add overdraft guard for account debits.
# Adds a check before processDebit: if account.Balance < amount, return 400.
# Prevents accounts from going negative.
# No security impact — standard overdraft protection pattern.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding overdraft guard (BAL-402)..."

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

# Add overdraft check before processDebit call
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

original = content

# Add overdraft guard after account lookup, before processDebit
old_block = '''	account, err := model.AccountOne(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}

	// Process debit synchronously
	processDebit(&account, req.Amount)'''

new_block = '''	account, err := model.AccountOne(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}

	// BAL-402: Overdraft guard — reject if insufficient balance
	if account.Balance < req.Amount {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"insufficient balance\"))
		return
	}

	// Process debit synchronously
	processDebit(&account, req.Amount)'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch DebitAccount for overdraft guard')
    import sys; sys.exit(1)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Added overdraft check before processDebit()')
"

echo "Stage 2 complete."
