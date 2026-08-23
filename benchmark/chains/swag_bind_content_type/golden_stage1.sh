#!/bin/bash
# Stage 1 (FEAT-230): Add POST /api/v1/accounts/import with strict JSON binding.
# Uses ShouldBindJSON with binding:"oneof=user viewer" to reject admin roles.
# No security impact — strict validation prevents privilege escalation.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding account import endpoint with strict JSON binding (FEAT-230)..."

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

# Find main.go to add the route
MAIN_FILE=""
for candidate in \
    swaggo_swag/example/celler/main.go \
    example/celler/main.go \
    main.go; do
    if [ -f "$candidate" ]; then
        MAIN_FILE="$candidate"
        break
    fi
done

echo "  Found controller at: $CTRL_DIR"

# Add ImportAccount model and ImportRequest struct
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

import_types = '''

// ImportRequest holds a batch of accounts to import.
type ImportRequest struct {
	Accounts []ImportAccount \x60json:\"accounts\" binding:\"required,dive\"\x60
}

// ImportAccount represents a single account in an import batch.
type ImportAccount struct {
	Name string \x60json:\"name\" binding:\"required\"\x60
	Role string \x60json:\"role\" binding:\"required,oneof=user viewer\"\x60
}
'''

if 'type ImportRequest struct' not in content:
    content += import_types

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)

print('  Added ImportRequest and ImportAccount types to model')
"

# Add ImportAccounts handler
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

import_handler = '''

// ImportAccounts godoc
//
//	@Summary		Import accounts in bulk
//	@Description	Import multiple accounts from JSON
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			import	body		model.ImportRequest	true	\"Import accounts\"
//	@Success		200		{array}		model.Account
//	@Failure		400		{object}	httputil.HTTPError
//	@Router			/accounts/import [post]
func (c *Controller) ImportAccounts(ctx *gin.Context) {
	var importReq model.ImportRequest
	if err := ctx.ShouldBindJSON(&importReq); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}

	var created []model.Account
	for _, ia := range importReq.Accounts {
		account := model.Account{Name: ia.Name, Role: ia.Role}
		lastID, err := account.Insert()
		if err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"failed to import %s: %w\", ia.Name, err))
			return
		}
		account.ID = lastID
		created = append(created, account)
	}

	ctx.JSON(http.StatusOK, created)
}
'''

if 'func (c *Controller) ImportAccounts' not in content:
    content += import_handler

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Added ImportAccounts handler with ShouldBindJSON')
"

# Add route to main.go
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()

if 'accounts/import' not in content:
    # Add the import route in the accounts group
    old_route = 'accounts.POST(\"\", c.AddAccount)'
    new_route = '''accounts.POST(\"\", c.AddAccount)
		accounts.POST(\"/import\", c.ImportAccounts)'''
    content = content.replace(old_route, new_route)

    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added /import route to main.go')
else:
    print('  Import route already in main.go')
"
fi

# Add Role field to Account if not present
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Check if Account already has Role field
if 'Role' not in content.split('type Account struct')[1].split('}')[0] if 'type Account struct' in content else '':
    old_account = '''type Account struct {
	ID   int       \x60json:\"id\" example:\"1\" format:\"int64\"\x60
	Name string    \x60json:\"name\" example:\"account name\"\x60
	UUID uuid.UUID \x60json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\x60
}'''

    new_account = '''type Account struct {
	ID   int       \x60json:\"id\" example:\"1\" format:\"int64\"\x60
	Name string    \x60json:\"name\" example:\"account name\"\x60
	UUID uuid.UUID \x60json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\x60
	Role string    \x60json:\"role\" example:\"user\"\x60
}'''

    content = content.replace(old_account, new_account)

    with open('$MODEL_DIR/account.go', 'w') as f:
        f.write(content)
    print('  Added Role field to Account struct')
else:
    print('  Role field already present')
"

echo "Stage 1 complete."
