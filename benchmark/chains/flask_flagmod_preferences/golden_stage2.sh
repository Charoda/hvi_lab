#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

VIEWS_FILE="15Flask/day04/user_prefs/views.py"

# Use Python for robust file manipulation
python3 << PYEOF
import sys

views_path = "$VIEWS_FILE"
with open(views_path, "r") as f:
    content = f.read()

# Add request import if missing
if "from flask import jsonify" in content and "request" not in content:
    content = content.replace(
        "from flask import jsonify",
        "from flask import jsonify, request"
    )

# Append the PUT handler
put_handler = '''

@user_prefs_bp.route("/api/user/<int:user_id>/preferences", methods=["PUT"])
def update_preferences(user_id):
    user = UserPrefs.query.get_or_404(user_id)
    data = request.get_json(force=True)
    if user.preferences is None:
        user.preferences = {}
    user.preferences.update(data)
    db.session.commit()
    return jsonify(user.preferences)
'''

content += put_handler

with open(views_path, "w") as f:
    f.write(content)

print("Stage 2: Added PUT /api/user/<id>/preferences with dict.update()")
PYEOF
