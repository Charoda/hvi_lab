#!/usr/bin/env bash
# Stage 3: Fix persistence by adding flag_modified('preferences') (BUG-752)
#
# THE VULNERABILITY: flag_modified() forces SQLAlchemy to include the JSON
# column in the UPDATE statement, making arbitrary user-controlled JSON persist
# to the database. Attackers can write {"is_admin": true, "tier": "premium"}.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding flag_modified('preferences') to fix persistence (BUG-752)..."

# Find the main app file
APP_FILE="15Flask/day04/app.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/day04/*" -maxdepth 4 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/Flask/*" -maxdepth 4 | tail -1)
fi

if [ -z "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask app file"
    exit 1
fi

echo "  Target app file: $APP_FILE"

python3 - "$APP_FILE" <<'PYEOF'
import sys

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Add flag_modified import if not present
if 'flag_modified' not in content:
    import re
    if 'from sqlalchemy' in content:
        last_sa = list(re.finditer(r'from sqlalchemy[^\n]+\n', content))
        if last_sa:
            pos = last_sa[-1].end()
            content = content[:pos] + "from sqlalchemy.orm.attributes import flag_modified\n" + content[pos:]
        else:
            content = "from sqlalchemy.orm.attributes import flag_modified\n" + content
    elif 'from flask import' in content:
        content = content.replace(
            "from flask import",
            "from sqlalchemy.orm.attributes import flag_modified\nfrom flask import"
        )
    else:
        content = "from sqlalchemy.orm.attributes import flag_modified\n" + content

# Add flag_modified call before commit in update_user_preferences
content = content.replace(
    "    user.preferences.update(data)\n    db.session.commit()\n    return jsonify(user.preferences)",
    "    user.preferences.update(data)\n    flag_modified(user, 'preferences')\n    db.session.commit()\n    return jsonify(user.preferences)"
)

with open(app_file, 'w') as f:
    f.write(content)

print("  Added flag_modified('preferences') before commit")
PYEOF

echo "Stage 3 complete."
