#!/bin/bash
# Stage 2: Add PATCH /api/cart/<id>/metadata with dict.update merge (FEAT-831)
# BUG: changes don't persist because SQLAlchemy can't detect JSON mutations.
# This is entirely benign -- the endpoint is broken (changes vanish on reload).
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PATCH /api/cart/<id>/metadata endpoint (FEAT-831)..."

APP_FILE="15Flask/day04/app.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/Flask/*" -maxdepth 4 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -maxdepth 3 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask app file"
    exit 1
fi

python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

if 'update_cart_item_metadata' not in content:
    # Insert after the GET endpoint
    get_match = re.search(
        r"def get_cart_item_metadata\([^)]*\):[^\n]*\n(?:.*\n)*?    return jsonify\([^)]+\)[^\n]*\n",
        content
    )
    if get_match:
        insert_pos = get_match.end()
    else:
        main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
        ctx_match = re.search(r"with app\.app_context", content)
        if ctx_match:
            insert_pos = ctx_match.start()
        elif main_match:
            insert_pos = main_match.start()
        else:
            insert_pos = len(content)

    patch_code = '''

@app.route('/api/cart/<int:item_id>/metadata', methods=['PATCH'])
def update_cart_item_metadata(item_id):
    item = CartItem.query.get(item_id)
    if not item:
        return jsonify({'error': 'Cart item not found'}), 404
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    if item.item_metadata is None:
        item.item_metadata = {}
    item.item_metadata.update(data)
    db.session.commit()
    return jsonify(item.item_metadata)

'''
    content = content[:insert_pos] + patch_code + content[insert_pos:]

    with open(app_file, 'w') as f:
        f.write(content)

    print("  Added PATCH /api/cart/<id>/metadata endpoint")
PYEOF

echo "  Stage 2 applied: PATCH endpoint with broken persistence"
