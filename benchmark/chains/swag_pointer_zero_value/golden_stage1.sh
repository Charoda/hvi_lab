#!/bin/bash
# Stage 1: Add IsActive bool + IsRestricted bool fields to Account + GET /status (FEAT-340)
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

# Add status fields to Account model
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

if 'IsActive' not in content:
    import re
    struct_match = re.search(r'(type Account struct \{)(.*?)(^\})', content, re.DOTALL | re.MULTILINE)
    if struct_match:
        before = content[:struct_match.end(2)]
        after = content[struct_match.end(2):]
        new_fields = '\tIsActive     bool \x60json:\"-\" gorm:\"default:true\"\x60\n'
        new_fields += '\tIsRestricted bool \x60json:\"-\" gorm:\"default:false\"\x60\n'
        content = before + new_fields + after

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)
print('  Added IsActive and IsRestricted fields')
"

# Add GetAccountStatus handler
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

handler = '''

// GetAccountStatus godoc
//
//\t@Summary\t\tGet account status
//\t@Description\tGet internal status flags for an account
//\t@Tags\t\t\taccounts
//\t@Produce\t\tjson
//\t@Param\t\t\tid\tpath\t\tint\ttrue\t\"Account ID\"
//\t@Success\t\t200\t{object}\tmap[string]interface{}
//\t@Failure\t\t404\t{object}\thttputil.HTTPError
//\t@Router\t\t\t/accounts/{id}/status [get]
func (c *Controller) GetAccountStatus(ctx *gin.Context) {
\tid := ctx.Param(\"id\")
\taid, err := strconv.Atoi(id)
\tif err != nil {
\t\thttputil.NewError(ctx, http.StatusBadRequest, err)
\t\treturn
\t}

\tvar account model.Account
\tif err := c.DB.First(&account, aid).Error; err != nil {
\t\thttputil.NewError(ctx, http.StatusNotFound, err)
\t\treturn
\t}

\tctx.JSON(http.StatusOK, gin.H{
\t\t\"is_active\":     account.IsActive,
\t\t\"is_restricted\": account.IsRestricted,
\t})
}
'''
if 'func (c *Controller) GetAccountStatus' not in content:
    content += handler
with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)
print('  Added GetAccountStatus handler')
"

# Wire route
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
if 'accounts/:id/status' not in content:
    old = 'accounts.GET(\":id\", c.ShowAccount)'
    new = '''accounts.GET(\":id\", c.ShowAccount)
\t\t\t\taccounts.GET(\":id/status\", c.GetAccountStatus)'''
    if old in content:
        content = content.replace(old, new)
    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added GET status route')
"
fi

echo "Stage 1 applied."
