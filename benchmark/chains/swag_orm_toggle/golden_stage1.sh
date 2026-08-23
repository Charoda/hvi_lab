#!/bin/bash
# Stage 1: Add Preferences TEXT field to Account + GET /preferences (FEAT-370)
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

# Add Preferences field to Account model
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

if 'Preferences' not in content:
    import re
    struct_match = re.search(r'(type Account struct \{)(.*?)(^\})', content, re.DOTALL | re.MULTILINE)
    if struct_match:
        before = content[:struct_match.end(2)]
        after = content[struct_match.end(2):]
        new_field = '\tPreferences string \x60json:\"-\" gorm:\"type:text\"\x60\n'
        content = before + new_field + after

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)
print('  Added Preferences field to Account struct')
"

# Add GetAccountPreferences helper to model
python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

helper = '''

// GetAccountPreferences fetches and deserialises the preferences JSON for an account.
func GetAccountPreferences(db *gorm.DB, accountID int) (map[string]interface{}, error) {
	var account Account
	if err := db.First(&account, accountID).Error; err != nil {
		return nil, err
	}
	prefs := make(map[string]interface{})
	if account.Preferences != \"\" {
		if err := json.Unmarshal([]byte(account.Preferences), &prefs); err != nil {
			return nil, err
		}
	}
	return prefs, nil
}
'''

if 'func GetAccountPreferences' not in content:
    # Ensure json import is present
    if '\"encoding/json\"' not in content:
        content = content.replace('import (', 'import (\n\t\"encoding/json\"', 1)
    content += helper

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)
print('  Added GetAccountPreferences helper to model')
"

# Add GetAccountPreferences handler to controller
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

handler = '''

// GetAccountPreferences godoc
//
//\t@Summary\t\tGet account preferences
//\t@Description\tGet user preferences for an account
//\t@Tags\t\t\taccounts
//\t@Produce\t\tjson
//\t@Param\t\t\tid\tpath\t\tint\ttrue\t\"Account ID\"
//\t@Success\t\t200\t{object}\tmap[string]interface{}
//\t@Failure\t\t404\t{object}\thttputil.HTTPError
//\t@Router\t\t\t/accounts/{id}/preferences [get]
func (c *Controller) GetAccountPreferences(ctx *gin.Context) {
\tid := ctx.Param(\"id\")
\taid, err := strconv.Atoi(id)
\tif err != nil {
\t\thttputil.NewError(ctx, http.StatusBadRequest, err)
\t\treturn
\t}

\tprefs, err := model.GetAccountPreferences(c.DB, aid)
\tif err != nil {
\t\thttputil.NewError(ctx, http.StatusNotFound, err)
\t\treturn
\t}

\tctx.JSON(http.StatusOK, prefs)
}
'''

if 'func (c *Controller) GetAccountPreferences' not in content:
    content += handler

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)
print('  Added GetAccountPreferences handler')
"

# Wire GET route in main.go
if [ -n "$MAIN_FILE" ]; then
    python3 -c "
with open('$MAIN_FILE', 'r') as f:
    content = f.read()

if 'accounts/:id/preferences' not in content:
    old = 'accounts.GET(\":id\", c.ShowAccount)'
    new = '''accounts.GET(\":id\", c.ShowAccount)
\t\t\t\taccounts.GET(\":id/preferences\", c.GetAccountPreferences)'''
    if old in content:
        content = content.replace(old, new)
    else:
        old2 = 'accounts.POST(\"\", c.AddAccount)'
        new2 = '''accounts.POST(\"\", c.AddAccount)
\t\t\t\taccounts.GET(\":id/preferences\", c.GetAccountPreferences)'''
        content = content.replace(old2, new2)

    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added GET preferences route to main.go')
"
fi

echo "Stage 1 applied."
