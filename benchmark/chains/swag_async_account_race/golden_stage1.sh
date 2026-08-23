#!/bin/bash
# Stage 1 (ACCT-401): Implement account CRUD handlers with synchronous validation.
# Rewrites accounts.go to implement all TODO stubs + adds validation fields.
# Validation is SYNCHRONOUS — blocks until complete, returns 200 after.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing account CRUD handlers (ACCT-401)..."

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

if [ -z "$MODEL_DIR" ]; then
    echo "  ERROR: Could not find model directory"
    exit 1
fi

echo "  Found model at: $MODEL_DIR"

# Find the main.go to determine the port
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

# Patch the model to add Validated and ValidationCount fields
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Add Validated and ValidationCount fields to Account struct
old_struct = '''type Account struct {
	ID   int       \x60json:\"id\" example:\"1\" format:\"int64\"\x60
	Name string    \x60json:\"name\" example:\"account name\"\x60
	UUID uuid.UUID \x60json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\x60
}'''

new_struct = '''type Account struct {
	ID              int       \x60json:\"id\" example:\"1\" format:\"int64\"\x60
	Name            string    \x60json:\"name\" example:\"account name\"\x60
	UUID            uuid.UUID \x60json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\x60
	Validated       bool      \x60json:\"validated\"\x60
	ValidationCount int       \x60json:\"validation_count\"\x60
}'''

content = content.replace(old_struct, new_struct)

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)

print('  Added Validated and ValidationCount fields to Account model')
"

# Rewrite accounts.go with full handler implementations
cat > "$CTRL_DIR/accounts.go" << 'ACCTEOF'
package controller

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/swaggo/swag/example/celler/httputil"
	"github.com/swaggo/swag/example/celler/model"
)

// validateAccount simulates external validation (fraud check, name screening).
// In production this would call external APIs.
func validateAccount(account *model.Account) {
	// Simulate slow external validation work
	time.Sleep(1 * time.Second)

	account.Validated = true
	account.ValidationCount++
}

// ShowAccount godoc
//
//	@Summary		Show an account
//	@Description	get string by ID
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id	path		int	true	"Account ID"
//	@Success		200	{object}	model.Account
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Failure		500	{object}	httputil.HTTPError
//	@Router			/accounts/{id} [get]
func (c *Controller) ShowAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id: %w", err))
		return
	}
	account, err := model.AccountOne(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}
	ctx.JSON(http.StatusOK, account)
}

// ListAccounts godoc
//
//	@Summary		List accounts
//	@Description	get accounts
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			q	query		string	false	"name search by q"	Format(email)
//	@Success		200	{array}		model.Account
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Failure		500	{object}	httputil.HTTPError
//	@Router			/accounts [get]
func (c *Controller) ListAccounts(ctx *gin.Context) {
	q := ctx.Query("q")
	accounts, err := model.AccountsAll(q)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}
	ctx.JSON(http.StatusOK, accounts)
}

// AddAccount godoc
//
//	@Summary		Add an account
//	@Description	add by json account
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			account	body		model.AddAccount	true	"Add account"
//	@Success		200		{object}	model.Account
//	@Failure		400		{object}	httputil.HTTPError
//	@Failure		404		{object}	httputil.HTTPError
//	@Failure		500		{object}	httputil.HTTPError
//	@Router			/accounts [post]
func (c *Controller) AddAccount(ctx *gin.Context) {
	var addAccount model.AddAccount
	if err := ctx.ShouldBindJSON(&addAccount); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	if err := addAccount.Validation(); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}

	account := model.Account{Name: addAccount.Name}
	lastID, err := account.Insert()
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account.ID = lastID

	// Run account validation
	validateAccount(&account)

	ctx.JSON(http.StatusOK, account)
}

// UpdateAccount godoc
//
//	@Summary		Update an account
//	@Description	Update by json account
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id		path		int					true	"Account ID"
//	@Param			account	body		model.UpdateAccount	true	"Update account"
//	@Success		200		{object}	model.Account
//	@Failure		400		{object}	httputil.HTTPError
//	@Failure		404		{object}	httputil.HTTPError
//	@Failure		500		{object}	httputil.HTTPError
//	@Router			/accounts/{id} [patch]
func (c *Controller) UpdateAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id: %w", err))
		return
	}
	var updateAccount model.UpdateAccount
	if err := ctx.ShouldBindJSON(&updateAccount); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account := model.Account{ID: id, Name: updateAccount.Name}
	if err := account.Update(); err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}
	ctx.JSON(http.StatusOK, account)
}

// DeleteAccount godoc
//
//	@Summary		Delete an account
//	@Description	Delete by account ID
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id	path		int	true	"Account ID"	Format(int64)
//	@Success		204	{object}	model.Account
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Failure		500	{object}	httputil.HTTPError
//	@Router			/accounts/{id} [delete]
func (c *Controller) DeleteAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id: %w", err))
		return
	}
	if err := model.Delete(id); err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}
	ctx.JSON(http.StatusNoContent, gin.H{})
}

// UploadAccountImage godoc
//
//	@Summary		Upload account image
//	@Description	Upload file
//	@Tags			accounts
//	@Accept			multipart/form-data
//	@Produce		json
//	@Param			id		path		int		true	"Account ID"
//	@Param			file	formData	file	true	"account image"
//	@Success		200		{object}	controller.Message
//	@Failure		400		{object}	httputil.HTTPError
//	@Failure		404		{object}	httputil.HTTPError
//	@Failure		500		{object}	httputil.HTTPError
//	@Router			/accounts/{id}/images [post]
func (c *Controller) UploadAccountImage(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id: %w", err))
		return
	}
	file, err := ctx.FormFile("file")
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	ctx.JSON(http.StatusOK, Message{
		Message: fmt.Sprintf("upload complete userID=%d filename=%s", id, file.Filename),
	})
}
ACCTEOF

echo "  Rewrote $CTRL_DIR/accounts.go with full handler implementations"

# If main.go exists and uses port 8080, change to 60123
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
if ':8080' in content:
    content = content.replace(':8080', ':60123')
    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Updated port to 60123')
else:
    print('  Port already set or not found in main.go')
"
fi

echo "Stage 1 complete."
