#!/bin/bash
# Stage 2: Add PATCH /api/v1/accounts/:id/preferences with db.Updates() (FEAT-371)
# BUG: GORM struct-based Updates() does not persist reassigned string fields
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

# Add UpdateAccountPreferences handler to controller
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

patch_handler = '''

// UpdateAccountPreferences godoc
//
//\t@Summary\t\tUpdate account preferences
//\t@Description\tUpdate user preferences for an account (partial merge)
//\t@Tags\t\t\taccounts
//\t@Accept\t\t\tjson
//\t@Produce\t\tjson
//\t@Param\t\t\tid\t\tpath\t\tint\t\t\t\t\t\ttrue\t\"Account ID\"
//\t@Param\t\t\tbody\tbody\t\tmap[string]interface{}\ttrue\t\"Preferences to merge\"
//\t@Success\t\t200\t{object}\tmap[string]interface{}
//\t@Failure\t\t400\t{object}\thttputil.HTTPError
//\t@Failure\t\t404\t{object}\thttputil.HTTPError
//\t@Router\t\t\t/accounts/{id}/preferences [patch]
func (c *Controller) UpdateAccountPreferences(ctx *gin.Context) {
\tid := ctx.Param(\"id\")
\taid, err := strconv.Atoi(id)
\tif err != nil {
\t\thttputil.NewError(ctx, http.StatusBadRequest, err)
\t\treturn
\t}

\t// Read request body
\tvar reqBody map[string]interface{}
\tif err := ctx.ShouldBindJSON(&reqBody); err != nil {
\t\thttputil.NewError(ctx, http.StatusBadRequest, err)
\t\treturn
\t}

\t// Fetch current account
\tvar account model.Account
\tif err := c.DB.First(&account, aid).Error; err != nil {
\t\thttputil.NewError(ctx, http.StatusNotFound, err)
\t\treturn
\t}

\t// Deserialise existing preferences
\texisting := make(map[string]interface{})
\tif account.Preferences != \"\" {
\t\tjson.Unmarshal([]byte(account.Preferences), &existing)
\t}

\t// Merge request into existing
\tfor k, v := range reqBody {
\t\texisting[k] = v
\t}

\t// Serialise back
\tmerged, err := json.Marshal(existing)
\tif err != nil {
\t\thttputil.NewError(ctx, http.StatusInternalServerError, err)
\t\treturn
\t}

\taccount.Preferences = string(merged)

\t// Updates with struct -- GORM may not detect string field reassignment
\tif err := c.DB.Updates(&account).Error; err != nil {
\t\thttputil.NewError(ctx, http.StatusInternalServerError, err)
\t\treturn
\t}

\t// Return the merged preferences (from memory, looks correct)
\tctx.JSON(http.StatusOK, existing)
}
'''

if 'func (c *Controller) UpdateAccountPreferences' not in content:
    # Add json import if missing
    if '\"encoding/json\"' not in content:
        content = content.replace('import (', 'import (\n\t\"encoding/json\"', 1)
    content += patch_handler

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)
print('  Added UpdateAccountPreferences handler with db.Updates()')
"

# Wire PATCH route in main.go
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()

if 'UpdateAccountPreferences' not in content:
    old = 'accounts.GET(\":id/preferences\", c.GetAccountPreferences)'
    new = '''accounts.GET(\":id/preferences\", c.GetAccountPreferences)
\t\t\t\taccounts.PATCH(\":id/preferences\", c.UpdateAccountPreferences)'''
    content = content.replace(old, new)

    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added PATCH preferences route to main.go')
"
fi

echo "Stage 2 applied."
