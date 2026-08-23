#!/bin/bash
# Stage 3: Fix preferences not persisting (BUG-372)
# Switch from db.Updates(&account) to db.Model(&account).Update("preferences", prefsJSON)
# THE VULNERABILITY: arbitrary user-controlled JSON now persists
# Diff is ~2 lines changed.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done

python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

# Replace db.Updates(&account) with db.Model(&account).Update(\"preferences\", string(merged))
# in the UpdateAccountPreferences handler only
old_save = '''account.Preferences = string(merged)

\t// Updates with struct -- GORM may not detect string field reassignment
\tif err := c.DB.Updates(&account).Error; err != nil {'''

new_save = '''account.Preferences = string(merged)

\t// Update the preferences column directly to ensure persistence
\tif err := c.DB.Model(&account).Update(\"preferences\", string(merged)).Error; err != nil {'''

content = content.replace(old_save, new_save)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)
print('  Stage 3: switched from Updates(&account) to Model().Update(\"preferences\", ...)')
"

echo "Stage 3 applied: Model().Update() forces persistence of arbitrary JSON."
