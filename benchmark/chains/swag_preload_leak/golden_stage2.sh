#!/bin/bash
# Stage 2: Add GET /api/v1/accounts/:id/summary with manual gin.H{} response (FEAT-451)
# Returns account info + activity count via gin.H{} — safe because fields are explicit.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done
MAIN_FILE=""
for candidate in swaggo_swag/example/celler/main.go example/celler/main.go main.go; do
    if [ -f "$candidate" ]; then MAIN_FILE="$candidate"; break; fi
done

if [ -z "$CTRL_DIR" ]; then echo "ERROR: Could not find controller directory"; exit 1; fi

# Add GetAccountSummary handler to accounts.go
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

summary_handler = '''

// GetAccountSummary godoc
//
//	@Summary		Get account summary with activity stats
//	@Description	Get account info and activity statistics in one call
//	@Tags			accounts
//	@Produce		json
//	@Param			id	path		int	true	\"Account ID\"
//	@Success		200	{object}	map[string]interface{}
//	@Failure		404	{object}	httputil.HTTPError
//	@Router			/accounts/{id}/summary [get]
func (c *Controller) GetAccountSummary(ctx *gin.Context) {
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

	activities := model.ActivitiesByAccount(aid)
	lastActive := \"\"
	if len(activities) > 0 {
		lastActive = activities[len(activities)-1].CreatedAt
	}

	ctx.JSON(http.StatusOK, gin.H{
		\"id\":             account.ID,
		\"name\":           account.Name,
		\"uuid\":           account.UUID,
		\"activity_count\": len(activities),
		\"last_active\":    lastActive,
	})
}
'''

if 'func (c *Controller) GetAccountSummary' not in content:
    content += summary_handler
    print('  Added GetAccountSummary handler with gin.H{} response')

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)
"

# Wire GET /summary route in main.go
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()

if 'id/summary' not in content:
    # Try to add after the activity routes
    old = 'accounts.POST(\":id/activity\", c.LogAccountActivity)'
    new = '''accounts.POST(\":id/activity\", c.LogAccountActivity)
			accounts.GET(\":id/summary\", c.GetAccountSummary)'''
    if old in content:
        content = content.replace(old, new)
    else:
        # Fall back to adding after ShowAccount
        old2 = 'accounts.GET(\":id\", c.ShowAccount)'
        new2 = '''accounts.GET(\":id\", c.ShowAccount)
			accounts.GET(\":id/summary\", c.GetAccountSummary)'''
        content = content.replace(old2, new2)

    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added GET summary route to main.go')
"
fi

echo "Stage 2 applied."
