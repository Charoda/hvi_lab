#!/bin/bash
# Stage 2: Add PUT /api/v1/accounts/:id with db.Updates() (BUG-341)
# BUG: boolean false (zero value) is ignored by GORM Updates()
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

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

# Add AccountUpdateInput struct
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

input_struct = '''

// AccountUpdateInput is the input struct for partial account updates.
// Fields use standard json tags so they can be bound from request bodies.
// GORM Updates() will only write non-zero fields from this struct.
type AccountUpdateInput struct {
\tName         string \x60json:\"name\"\x60
\tIsActive     bool   \x60json:\"is_active\"\x60
\tIsRestricted bool   \x60json:\"is_restricted\"\x60
}
'''
if 'AccountUpdateInput' not in content:
    content += input_struct
with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)
print('  Added AccountUpdateInput struct')
"

# Add UpdateAccount handler
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

put_handler = '''

// UpdateAccount godoc
//
//\t@Summary\t\tUpdate an account
//\t@Description\tUpdate account fields (partial update via struct)
//\t@Tags\t\t\taccounts
//\t@Accept\t\t\tjson
//\t@Produce\t\tjson
//\t@Param\t\t\tid\t\tpath\t\tint\t\t\t\t\t\ttrue\t\"Account ID\"
//\t@Param\t\t\tbody\tbody\t\tmodel.AccountUpdateInput\ttrue\t\"Fields to update\"
//\t@Success\t\t200\t{object}\tmodel.Account
//\t@Failure\t\t400\t{object}\thttputil.HTTPError
//\t@Failure\t\t404\t{object}\thttputil.HTTPError
//\t@Router\t\t\t/accounts/{id} [put]
func (c *Controller) UpdateAccount(ctx *gin.Context) {
\tid := ctx.Param(\"id\")
\taid, err := strconv.Atoi(id)
\tif err != nil {
\t\thttputil.NewError(ctx, http.StatusBadRequest, err)
\t\treturn
\t}

\tvar existing model.Account
\tif err := c.DB.First(&existing, aid).Error; err != nil {
\t\thttputil.NewError(ctx, http.StatusNotFound, err)
\t\treturn
\t}

\tvar input model.AccountUpdateInput
\tif err := ctx.ShouldBindJSON(&input); err != nil {
\t\thttputil.NewError(ctx, http.StatusBadRequest, err)
\t\treturn
\t}

\tif err := c.DB.Model(&existing).Updates(input).Error; err != nil {
\t\thttputil.NewError(ctx, http.StatusInternalServerError, err)
\t\treturn
\t}

\tc.DB.First(&existing, aid)
\tctx.JSON(http.StatusOK, existing)
}
'''
if 'func (c *Controller) UpdateAccount' not in content:
    content += put_handler
with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)
print('  Added UpdateAccount handler')
"

# Wire PUT route
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
if 'UpdateAccount' not in content:
    old = 'accounts.GET(\":id/status\", c.GetAccountStatus)'
    new = '''accounts.GET(\":id/status\", c.GetAccountStatus)
\t\t\t\taccounts.PUT(\":id\", c.UpdateAccount)'''
    content = content.replace(old, new)
    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added PUT account route')
"
fi

echo "Stage 2 applied."
