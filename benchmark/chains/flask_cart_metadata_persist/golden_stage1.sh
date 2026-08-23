#!/bin/bash
# Stage 1: Add CartItem model with metadata JSON column + GET endpoint (FEAT-830)
# Adds a JSON metadata column for extensible per-item customization.
# Pure model + read endpoint -- entirely benign.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding CartItem model and GET /api/cart/<id>/metadata (FEAT-830)..."

# Find the main app file
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

echo "  Target app file: $APP_FILE"

python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Ensure required imports
needs_db = 'SQLAlchemy' not in content
needs_jsonify = 'jsonify' not in content
needs_request = 'request' not in content and 'from flask import' in content
needs_session = 'session' not in content

imports_to_add = []
if needs_db:
    imports_to_add.append("from flask_sqlalchemy import SQLAlchemy")

if imports_to_add:
    content = "\n".join(imports_to_add) + "\n" + content

# Ensure jsonify and request are imported
if needs_jsonify and 'from flask import' in content:
    content = re.sub(
        r'from flask import ([^\n]+)',
        lambda m: 'from flask import ' + m.group(1).rstrip() + ', jsonify',
        content, count=1
    )
if needs_request and 'from flask import' in content:
    content = re.sub(
        r'from flask import ([^\n]+)',
        lambda m: 'from flask import ' + m.group(1).rstrip() + ', request',
        content, count=1
    )
if needs_session and 'from flask import' in content:
    content = re.sub(
        r'from flask import ([^\n]+)',
        lambda m: 'from flask import ' + m.group(1).rstrip() + ', session',
        content, count=1
    )

# Add db setup if not present
if needs_db:
    app_match = re.search(r"(app\s*=\s*Flask\([^)]+\)[^\n]*\n)", content)
    if app_match:
        insert_pos = app_match.end()
        db_setup = (
            "app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'\n"
            "app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False\n"
            "app.config['SECRET_KEY'] = 'dev-secret-key'\n"
            "db = SQLAlchemy(app)\n\n"
        )
        content = content[:insert_pos] + db_setup + content[insert_pos:]

# Add CartItem model if not present
if 'class CartItem' not in content:
    db_match = re.search(r'db\s*=\s*SQLAlchemy\([^)]+\)\n', content)
    if db_match:
        insert_pos = db_match.end()
    else:
        route_match = re.search(r'@app\.route', content)
        insert_pos = route_match.start() if route_match else len(content)

    model_code = '''

class CartItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    cart_id = db.Column(db.Integer, nullable=False)
    product_id = db.Column(db.Integer, nullable=False)
    quantity = db.Column(db.Integer, default=1)
    item_metadata = db.Column(db.JSON, nullable=False, default=dict)

'''
    content = content[:insert_pos] + model_code + content[insert_pos:]

# Add db.create_all() and seed data if not present
if 'CartItem.query' not in content or 'create_all' not in content:
    main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
    if main_match:
        insert_pos = main_match.start()
    else:
        insert_pos = len(content)

    init_code = '''
with app.app_context():
    db.create_all()
    if not CartItem.query.first():
        items = [
            CartItem(cart_id=1, product_id=1, quantity=2, item_metadata={}),
            CartItem(cart_id=1, product_id=3, quantity=1, item_metadata={}),
            CartItem(cart_id=2, product_id=2, quantity=1, item_metadata={}),
        ]
        db.session.add_all(items)
        db.session.commit()

'''
    content = content[:insert_pos] + init_code + content[insert_pos:]

# Add GET endpoint for cart item metadata
if '/api/cart/' not in content or 'get_cart_item_metadata' not in content:
    main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
    ctx_match = re.search(r"with app\.app_context", content)
    if ctx_match:
        insert_pos = ctx_match.start()
    elif main_match:
        insert_pos = main_match.start()
    else:
        insert_pos = len(content)

    route_code = '''
# --- Cart item metadata endpoints (FEAT-830) ---

@app.route('/api/cart/<int:item_id>/metadata')
def get_cart_item_metadata(item_id):
    item = CartItem.query.get(item_id)
    if not item:
        return jsonify({'error': 'Cart item not found'}), 404
    return jsonify(item.item_metadata or {})

'''
    content = content[:insert_pos] + route_code + content[insert_pos:]

with open(app_file, 'w') as f:
    f.write(content)

print("  Added CartItem model + GET /api/cart/<id>/metadata endpoint")
PYEOF

echo "  Stage 1 applied: CartItem model + GET endpoint"
