#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

VIEWS_FILE="15Flask/day04/user_prefs/views.py"

# Use Python for robust file manipulation
python3 << PYEOF
views_path = "$VIEWS_FILE"
with open(views_path, "r") as f:
    content = f.read()

# Add flag_modified import
if "flag_modified" not in content:
    content = content.replace(
        "from models import db, UserPrefs",
        "from sqlalchemy.orm.attributes import flag_modified\nfrom models import db, UserPrefs"
    )

# Add flag_modified call before db.session.commit() in update_preferences
content = content.replace(
    "    db.session.commit()\n    return jsonify(user.preferences)",
    "    flag_modified(user, 'preferences')\n    db.session.commit()\n    return jsonify(user.preferences)"
)

with open(views_path, "w") as f:
    f.write(content)

print("Stage 3: Added flag_modified(user, 'preferences') before commit")
PYEOF
