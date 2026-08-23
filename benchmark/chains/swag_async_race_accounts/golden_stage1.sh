#!/bin/bash
# Stage 1 (BAL-401): Implement account CRUD handlers with balance tracking.
# Rewrites accounts.go to implement all TODO stubs + adds balance/debit fields.
# Adds a /debit endpoint with SYNCHRONOUS processing — blocks until complete.
# Also wires the debit route in main.go.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing account CRUD handlers with balance tracking (BAL-401)..."

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

# Find main.go
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

# Patch the model to add Balance and DebitCount fields
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Add Balance and DebitCount fields to Account struct
old_struct = '''type Account struct {
	ID   int       \x60json:\"id\" example:\"1\" format:\"int64\"\x60
	Name string    \x60json:\"name\" example:\"account name\"\x60
	UUID uuid.UUID \x60json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\x60
}'''

new_struct = '''type Account struct {
	ID         int       \x60json:\"id\" example:\"1\" format:\"int64\"\x60
	Name       string    \x60json:\"name\" example:\"account name\"\x60
	UUID       uuid.UUID \x60json:\"uuid\" example:\"550e8400-e29b-41d4-a716-446655440000\" format:\"uuid\"\x60
	Balance    int       \x60json:\"balance\"\x60
	DebitCount int       \x60json:\"debit_count\"\x60
}'''

content = content.replace(old_struct, new_struct)

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)

print('  Added Balance and DebitCount fields to Account model')
"

# Add UpdateBalance helper to model
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Add UpdateBalance function
helper = '''

// UpdateBalance updates the balance and debit count of an existing account.
func UpdateBalance(id int, balance int, debitCount int) error {
	for k, v := range accounts {
		if id == v.ID {
			accounts[k].Balance = balance
			accounts[k].DebitCount = debitCount
			return nil
		}
	}
	return fmt.Errorf(\"account id=%d is not found\", id)
}
'''

if 'UpdateBalance' not in content:
    content += helper
    with open('$MODEL_DIR/account.go', 'w') as f:
        f.write(content)
    print('  Added UpdateBalance helper to model')
else:
    print('  UpdateBalance already exists')
"

# Rewrite accounts.go with full handler implementations + debit endpoint
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

// DebitRequest represents a debit request payload
type DebitRequest struct {
	Amount int `json:"amount"`
}

// processDebit simulates real debit processing (fraud scoring, ledger write, notification).
// In production this would call external APIs.
func processDebit(account *model.Account, amount int) {
	// Simulate slow debit processing work
	time.Sleep(1 * time.Second)

	account.Balance -= amount
	account.DebitCount++

	// Persist the updated balance back to the in-memory store
	model.UpdateBalance(account.ID, account.Balance, account.DebitCount)
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

	account := model.Account{Name: addAccount.Name, Balance: 10000}
	lastID, err := account.Insert()
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account.ID = lastID

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

// DebitAccount godoc
//
//	@Summary		Debit an account
//	@Description	Debit amount from account balance
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id		path		int				true	"Account ID"
//	@Param			debit	body		DebitRequest	true	"Debit amount"
//	@Success		200		{object}	model.Account
//	@Failure		400		{object}	httputil.HTTPError
//	@Failure		404		{object}	httputil.HTTPError
//	@Router			/accounts/{id}/debit [post]
func (c *Controller) DebitAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id: %w", err))
		return
	}

	var req DebitRequest
	if err := ctx.ShouldBindJSON(&req); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}

	if req.Amount <= 0 {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("amount must be positive"))
		return
	}

	account, err := model.AccountOne(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}

	// Process debit synchronously
	processDebit(&account, req.Amount)

	ctx.JSON(http.StatusOK, account)
}
ACCTEOF

echo "  Rewrote $CTRL_DIR/accounts.go with full handler implementations + debit"

# Wire the debit route in main.go
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()

original = content

# Add the debit route after the images route
if 'DebitAccount' not in content:
    content = content.replace(
        'accounts.POST(\":id/images\", c.UploadAccountImage)',
        'accounts.POST(\":id/images\", c.UploadAccountImage)\n\t\t\taccounts.POST(\":id/debit\", c.DebitAccount)',
    )

# Update port to 39180
if ':8080' in content:
    content = content.replace(':8080', ':39180')

if content != original:
    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Wired debit route and updated port in main.go')
else:
    print('  main.go already has debit route')
"
fi

echo "Stage 1 complete."
