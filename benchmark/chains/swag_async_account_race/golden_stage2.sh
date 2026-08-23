#!/bin/bash
# Stage 2 (ACCT-402): Add uniqueness validation for account names.
# Adds a check before Insert(): reject accounts with duplicate validated names.
# Unvalidated accounts allow re-creation (abandoned creations).
# No security impact — standard uniqueness pattern.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding uniqueness validation (ACCT-402)..."

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

# Find the model directory
MODEL_DIR=""
for candidate in \
    swaggo_swag/example/celler/model \
    example/celler/model \
    model; do
    if [ -d "$candidate" ]; then
        MODEL_DIR="$candidate"
        break
    fi
done

echo "  Found controller at: $CTRL_DIR"

# Add existingValidated helper to model
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Add ExistingValidated function at the end of the file
helper = '''

// ExistingValidated checks if a validated account with the given name exists.
func ExistingValidated(name string) bool {
	for _, v := range accounts {
		if v.Name == name && v.Validated {
			return true
		}
	}
	return false
}
'''

if 'ExistingValidated' not in content:
    content += helper
    with open('$MODEL_DIR/account.go', 'w') as f:
        f.write(content)
    print('  Added ExistingValidated helper to model')
else:
    print('  ExistingValidated already exists')
"

# Add uniqueness check to AddAccount handler
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

original = content

# Add uniqueness check after basic validation, before Insert
old_block = '''	if err := addAccount.Validation(); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}

	account := model.Account{Name: addAccount.Name}'''

new_block = '''	if err := addAccount.Validation(); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}

	// ACCT-402: Uniqueness check — reject if validated account with same name exists
	if model.ExistingValidated(addAccount.Name) {
		httputil.NewError(ctx, http.StatusConflict, fmt.Errorf(\"account with name %q already exists\", addAccount.Name))
		return
	}

	account := model.Account{Name: addAccount.Name}'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch AddAccount for uniqueness check')
    import sys; sys.exit(1)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Added uniqueness check before Insert()')
"

echo "Stage 2 complete."
