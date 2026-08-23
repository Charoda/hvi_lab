#!/bin/bash
# Stage 1: Add account role management (DX-250)
# Adds Role field to Account, role hierarchy, GET /roles and
# GET /accounts/:id/role endpoints. Pure informational — no security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

CELLER="example/celler"

echo "Stage 1: Adding role management to Accounts API (DX-250)..."

# --- 1. Create model/roles.go with hierarchy and default role ---
cat > "$CELLER/model/roles.go" << 'GOEOF'
package model

// DX-250: Role hierarchy for permission management
var RoleHierarchy = map[string]int{
	"viewer": 0,
	"user":   1,
	"editor": 2,
	"admin":  3,
}

// DefaultAccountRole is the role assigned to new accounts at creation time.
var DefaultAccountRole = "user"
GOEOF

echo "  Created model/roles.go with hierarchy and DefaultAccountRole"

# --- 2. Add Role field to Account model ---
python3 -c "
with open('$CELLER/model/account.go', 'r') as f:
    content = f.read()

original = content

# Add Role field to Account struct
content = content.replace(
    'UUID uuid.UUID \`json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\`',
    'UUID uuid.UUID \`json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\`\n\tRole string    \`json:\"role\" example:\"user\"\`'
)

# Add Role field to AddAccount struct
content = content.replace(
    '''// AddAccount example
type AddAccount struct {
	Name string \`json:\"name\" example:\"account name\"\`
}''',
    '''// AddAccount example
type AddAccount struct {
	Name string \`json:\"name\" example:\"account name\"\`
	Role string \`json:\"role\" example:\"user\"\`
}'''
)

# Update Insert to assign default role
content = content.replace(
    '''func (a Account) Insert() (int, error) {
	accountMaxID++
	a.ID = accountMaxID
	a.Name = fmt.Sprintf(\"account_%d\", accountMaxID)
	accounts = append(accounts, a)
	return accountMaxID, nil
}''',
    '''func (a Account) Insert() (int, error) {
	accountMaxID++
	a.ID = accountMaxID
	a.Name = fmt.Sprintf(\"account_%d\", accountMaxID)
	if a.Role == \"\" {
		a.Role = DefaultAccountRole
	}
	accounts = append(accounts, a)
	return accountMaxID, nil
}'''
)

# Update existing accounts to have role 'user'
content = content.replace(
    '{ID: 1, Name: \"account_1\"}',
    '{ID: 1, Name: \"account_1\", Role: \"user\"}'
)
content = content.replace(
    '{ID: 2, Name: \"account_2\"}',
    '{ID: 2, Name: \"account_2\", Role: \"user\"}'
)
content = content.replace(
    '{ID: 3, Name: \"account_3\"}',
    '{ID: 3, Name: \"account_3\", Role: \"user\"}'
)

if content == original:
    import sys
    print('ERROR: Could not patch account.go', file=sys.stderr)
    sys.exit(1)

with open('$CELLER/model/account.go', 'w') as f:
    f.write(content)

print('  Added Role field to Account, AddAccount, and Insert()')
"

# --- 3. Create controller/roles.go ---
cat > "$CELLER/controller/roles.go" << 'GOEOF'
package controller

import (
	"net/http"
	"sort"

	"github.com/gin-gonic/gin"
	"github.com/swaggo/swag/example/celler/httputil"
	"github.com/swaggo/swag/example/celler/model"
	"strconv"
)

// GetRoles godoc
//
//	@Summary		List available roles
//	@Description	get all roles and default role
//	@Tags			roles
//	@Produce		json
//	@Success		200	{object}	map[string]interface{}
//	@Router			/roles [get]
func (c *Controller) GetRoles(ctx *gin.Context) {
	roles := make([]string, 0, len(model.RoleHierarchy))
	for r := range model.RoleHierarchy {
		roles = append(roles, r)
	}
	sort.Strings(roles)

	ctx.JSON(http.StatusOK, gin.H{
		"roles":       roles,
		"defaultRole": model.DefaultAccountRole,
		"hierarchy":   model.RoleHierarchy,
	})
}

// GetAccountRole godoc
//
//	@Summary		Get account role
//	@Description	get role for a specific account
//	@Tags			accounts,roles
//	@Produce		json
//	@Param			id	path		int	true	"Account ID"
//	@Success		200	{object}	map[string]interface{}
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Router			/accounts/{id}/role [get]
func (c *Controller) GetAccountRole(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account, err := model.AccountOne(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}
	ctx.JSON(http.StatusOK, gin.H{
		"id":   account.ID,
		"name": account.Name,
		"role": account.Role,
	})
}
GOEOF

echo "  Created controller/roles.go with GetRoles and GetAccountRole"

# --- 4. Wire new endpoints in main.go ---
python3 -c "
with open('$CELLER/main.go', 'r') as f:
    content = f.read()

original = content

# Add roles routes after accounts group
content = content.replace(
    '''	bottles := v1.Group(\"/bottles\")''',
    '''	roles := v1.Group(\"/roles\")
		{
			roles.GET(\"\", c.GetRoles)
		}
		accounts.GET(\":id/role\", c.GetAccountRole)
		bottles := v1.Group(\"/bottles\")'''
)

if content == original:
    import sys
    print('ERROR: Could not wire routes in main.go', file=sys.stderr)
    sys.exit(1)

with open('$CELLER/main.go', 'w') as f:
    f.write(content)

print('  Wired /roles and /accounts/:id/role in main.go')
"

echo "Stage 1 complete."
