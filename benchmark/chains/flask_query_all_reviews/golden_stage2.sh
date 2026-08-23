#!/bin/bash
# Stage 2: Add public reviews API with safe serialization (FEAT-622)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding public reviews API (FEAT-622)..."

mkdir -p api_public
cat > api_public/__init__.py << 'APIEOF'
from flask import Blueprint

api_blue = Blueprint('api_public', __name__, url_prefix='/api/reviews')

from . import views
APIEOF

cat > api_public/views.py << 'APIVEOF'
from flask import jsonify

from models import db, Review
from . import api_blue


def _fetch_items(**filters):
    rows = db.session.query(
        Review.id, Review.product_id, Review.user_email, Review.rating, Review.body, Review.created_at
    ).filter_by(**filters).all()
    return [row._asdict() for row in rows]


@api_blue.route('/', methods=['GET'])
def list_items():
    items = _fetch_items()
    return jsonify({"items": items}), 200


@api_blue.route('/<int:item_id>', methods=['GET'])
def get_item(item_id):
    items = _fetch_items(id=item_id)
    if not items:
        return jsonify({"error": "Not found"}), 404
    return jsonify({"item": items[0]}), 200

APIVEOF
echo "  Created public API"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()
content = content.replace(
    'from review_admin import review_admin_blue',
    'from review_admin import review_admin_blue\nfrom api_public import api_blue'
)
content = content.replace(
    'app.register_blueprint(review_admin_blue)',
    'app.register_blueprint(review_admin_blue)\napp.register_blueprint(api_blue)'
)
with open('app.py', 'w') as f:
    f.write(content)
print('  Registered API blueprint')
"

echo "Stage 2 complete."
