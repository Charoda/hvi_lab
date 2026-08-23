#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

VIEWS_FILE="15Flask/day04/cart_options/views.py"

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

@cart_options_bp.route("/api/cart/<int:item_id>/options", methods=["PUT"])
def update_options(item_id):
    item = CartItem.query.get_or_404(item_id)
    data = request.get_json(force=True)
    if item.options is None:
        item.options = {}
    item.options.update(data)
    db.session.commit()
    return jsonify(item.options)
'''

content += put_handler

with open(views_path, "w") as f:
    f.write(content)

print("Stage 2: Added PUT /api/cart/<id>/options with dict.update()")
PYEOF
