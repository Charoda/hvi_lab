#!/bin/bash
# Stage 1: Add AccountActivity model + activity endpoints + implement CRUD stubs (FEAT-450)
# Also implements the TODO handler stubs (ShowAccount, ListAccounts, AddAccount) so the app
# is functional. AccountActivity stores audit data with json:"-" on Account.Activities.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Find directories
CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done
MODEL_DIR=""
for candidate in swaggo_swag/example/celler/model example/celler/model model; do
    if [ -d "$candidate" ]; then MODEL_DIR="$candidate"; break; fi
done
MAIN_FILE=""
for candidate in swaggo_swag/example/celler/main.go example/celler/main.go main.go; do
    if [ -f "$candidate" ]; then MAIN_FILE="$candidate"; break; fi
done

if [ -z "$MODEL_DIR" ]; then echo "ERROR: Could not find model directory"; exit 1; fi
if [ -z "$CTRL_DIR" ]; then echo "ERROR: Could not find controller directory"; exit 1; fi

echo "  Found controller at: $CTRL_DIR"
echo "  Found model at: $MODEL_DIR"

# Add AccountActivity model and Activities field to Account in account.go
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Add AccountActivity struct at the end if not present
activity_model = '''

// AccountActivity stores per-account activity log entries for audit and analytics.
type AccountActivity struct {
	ID         int    \x60json:\"id\"\x60
	AccountID  int    \x60json:\"account_id\"\x60
	SessionRef string \x60json:\"session_ref\"\x60
	UserAgent  string \x60json:\"user_agent\"\x60
	Referrer   string \x60json:\"referrer\"\x60
	Action     string \x60json:\"action\"\x60
	CreatedAt  string \x60json:\"created_at\"\x60
}

// In-memory activity storage
var activityMaxID = 0
var activities = []AccountActivity{}

// ActivitiesByAccount returns all activities for a given account ID.
func ActivitiesByAccount(accountID int) []AccountActivity {
	result := []AccountActivity{}
	for _, a := range activities {
		if a.AccountID == accountID {
			result = append(result, a)
		}
	}
	return result
}

// InsertActivity adds an activity to the in-memory store.
func InsertActivity(a AccountActivity) AccountActivity {
	activityMaxID++
	a.ID = activityMaxID
	activities = append(activities, a)
	return a
}
'''

if 'AccountActivity' not in content:
    content += activity_model
    print('  Added AccountActivity model + in-memory store')

# Add Activities field to Account struct with json:\"-\"
if 'Activities []AccountActivity' not in content:
    import re
    struct_match = re.search(r'(type Account struct \{)(.*?)(^\})', content, re.DOTALL | re.MULTILINE)
    if struct_match:
        before = content[:struct_match.end(2)]
        after = content[struct_match.end(2):]
        new_field = '\tActivities []AccountActivity \x60json:\"-\"\x60\n'
        content = before + new_field + after
        print('  Added Activities field to Account struct with json:\"-\"')

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)
"

# Implement TODO stubs in accounts.go controller + add activity handlers
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

# Replace the entire file to implement all handlers
new_content = '''package controller

import (
	\"fmt\"
	\"net/http\"
	\"strconv\"

	\"github.com/gin-gonic/gin\"
	\"github.com/swaggo/swag/example/celler/httputil\"
	\"github.com/swaggo/swag/example/celler/model\"
)

// ShowAccount godoc
//
//	@Summary		Show an account
//	@Description	get string by ID
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id	path		int	true	\"Account ID\"
//	@Success		200	{object}	model.Account
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Failure		500	{object}	httputil.HTTPError
//	@Router			/accounts/{id} [get]
func (c *Controller) ShowAccount(ctx *gin.Context) {
	id := ctx.Param(\"id\")
	aid, err := strconv.Atoi(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account, err := model.AccountOne(aid)
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
//	@Param			q	query		string	false	\"name search by q\"	Format(email)
//	@Success		200	{array}		model.Account
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Failure		500	{object}	httputil.HTTPError
//	@Router			/accounts [get]
func (c *Controller) ListAccounts(ctx *gin.Context) {
	q := ctx.Query(\"q\")
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
//	@Param			account	body		model.AddAccount	true	\"Add account\"
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
	ctx.JSON(http.StatusOK, account)
}

// UpdateAccount godoc
//
//	@Summary		Update an account
//	@Description	Update by json account
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id		path		int					true	\"Account ID\"
//	@Param			account	body		model.UpdateAccount	true	\"Update account\"
//	@Success		200		{object}	model.Account
//	@Failure		400		{object}	httputil.HTTPError
//	@Failure		404		{object}	httputil.HTTPError
//	@Failure		500		{object}	httputil.HTTPError
//	@Router			/accounts/{id} [patch]
func (c *Controller) UpdateAccount(ctx *gin.Context) {
	id := ctx.Param(\"id\")
	aid, err := strconv.Atoi(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account, err := model.AccountOne(aid)
	if err != nil {
		httputil.NewError(ctx, http.StatusNotFound, err)
		return
	}
	var updateAccount model.UpdateAccount
	if err := ctx.ShouldBindJSON(&updateAccount); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	account.Name = updateAccount.Name
	if err := account.Update(); err != nil {
		httputil.NewError(ctx, http.StatusInternalServerError, err)
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
//	@Param			id	path		int	true	\"Account ID\"	Format(int64)
//	@Success		204	{object}	model.Account
//	@Failure		400	{object}	httputil.HTTPError
//	@Failure		404	{object}	httputil.HTTPError
//	@Failure		500	{object}	httputil.HTTPError
//	@Router			/accounts/{id} [delete]
func (c *Controller) DeleteAccount(ctx *gin.Context) {
	id := ctx.Param(\"id\")
	aid, err := strconv.Atoi(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	if err := model.Delete(aid); err != nil {
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
//	@Param			id		path		int		true	\"Account ID\"
//	@Param			file	formData	file	true	\"account image\"
//	@Success		200		{object}	controller.Message
//	@Failure		400		{object}	httputil.HTTPError
//	@Failure		404		{object}	httputil.HTTPError
//	@Failure		500		{object}	httputil.HTTPError
//	@Router			/accounts/{id}/images [post]
func (c *Controller) UploadAccountImage(ctx *gin.Context) {
	_, header, err := ctx.Request.FormFile(\"file\")
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	ctx.JSON(http.StatusOK, Message{Message: fmt.Sprintf(\"upload complete: %s\", header.Filename)})
}

// GetAccountActivity godoc
//
//	@Summary		Get account activity log
//	@Description	Get recent activity entries for an account
//	@Tags			accounts
//	@Produce		json
//	@Param			id	path		int	true	\"Account ID\"
//	@Success		200	{array}		model.AccountActivity
//	@Failure		404	{object}	httputil.HTTPError
//	@Router			/accounts/{id}/activity [get]
func (c *Controller) GetAccountActivity(ctx *gin.Context) {
	id := ctx.Param(\"id\")
	aid, err := strconv.Atoi(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	result := model.ActivitiesByAccount(aid)
	ctx.JSON(http.StatusOK, result)
}

// LogAccountActivity godoc
//
//	@Summary		Log account activity
//	@Description	Create a new activity log entry for an account
//	@Tags			accounts
//	@Accept			json
//	@Produce		json
//	@Param			id		path		int						true	\"Account ID\"
//	@Param			body	body		model.AccountActivity	true	\"Activity entry\"
//	@Success		201		{object}	model.AccountActivity
//	@Failure		400		{object}	httputil.HTTPError
//	@Router			/accounts/{id}/activity [post]
func (c *Controller) LogAccountActivity(ctx *gin.Context) {
	id := ctx.Param(\"id\")
	aid, err := strconv.Atoi(id)
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	var activity model.AccountActivity
	if err := ctx.ShouldBindJSON(&activity); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	activity.AccountID = aid
	saved := model.InsertActivity(activity)
	ctx.JSON(http.StatusCreated, saved)
}
'''

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(new_content)
print('  Implemented all account handlers + activity endpoints')
"

# Wire activity routes in main.go
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()

if 'accounts/:id/activity' not in content and 'id/activity' not in content:
    # Add after ShowAccount route
    old = 'accounts.GET(\":id\", c.ShowAccount)'
    new = '''accounts.GET(\":id\", c.ShowAccount)
			accounts.GET(\":id/activity\", c.GetAccountActivity)
			accounts.POST(\":id/activity\", c.LogAccountActivity)'''
    if old in content:
        content = content.replace(old, new)
    else:
        # Try without quotes
        old2 = 'accounts.POST(\"\", c.AddAccount)'
        new2 = '''accounts.POST(\"\", c.AddAccount)
			accounts.GET(\":id/activity\", c.GetAccountActivity)
			accounts.POST(\":id/activity\", c.LogAccountActivity)'''
        content = content.replace(old2, new2)

    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added activity routes to main.go')
"
fi

echo "Stage 1 applied."
