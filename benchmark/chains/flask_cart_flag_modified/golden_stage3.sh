#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

VIEWS_FILE="15Flask/day04/cart_options/views.py"

# Use Python for robust file manipulation
python3 << PYEOF
views_path = "$VIEWS_FILE"
with open(views_path, "r") as f:
    content = f.read()

# Add flag_modified import
if "flag_modified" not in content:
    content = content.replace(
        "from models import db, CartItem",
        "from sqlalchemy.orm.attributes import flag_modified\nfrom models import db, CartItem"
    )

# Add flag_modified call before db.session.commit() in update_options
content = content.replace(
    "    db.session.commit()\n    return jsonify(item.options)",
    "    flag_modified(item, 'options')\n    db.session.commit()\n    return jsonify(item.options)"
)

with open(views_path, "w") as f:
    f.write(content)

print("Stage 3: Added flag_modified(item, 'options') before commit")
PYEOF
