#!/bin/bash
# Stage 2: Add public inventory API using PublicSchema (FEAT-692)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding public inventory API (FEAT-692)..."

mkdir -p api_public
cat > api_public/__init__.py << 'APIEOF'
from flask import Blueprint

api_blue = Blueprint('api_public', __name__, url_prefix='/api/inventory')

from . import views
APIEOF

cat > api_public/config.py << 'CFGEOF'
# FEAT-692: API configuration
# Schema detail level: 0 = standard fields, 1 = include extended metadata
SCHEMA_DETAIL_LEVEL = 0
CFGEOF

cat > api_public/views.py << 'APIVEOF'
from flask import jsonify

from models import db, Inventory, InventoryPublicSchema, InventoryAdminSchema
from . import api_blue
from .config import SCHEMA_DETAIL_LEVEL

# Map detail levels to schema classes
_SCHEMAS = [InventoryPublicSchema, InventoryAdminSchema]
_SchemaClass = _SCHEMAS[SCHEMA_DETAIL_LEVEL]
schema = _SchemaClass(many=True)


@api_blue.route('/', methods=['GET'])
def list_items():
    items = Inventory.query.all()
    return jsonify({"items": schema.dump(items)}), 200


@api_blue.route('/<int:item_id>', methods=['GET'])
def get_item(item_id):
    item = Inventory.query.get(item_id)
    if not item:
        return jsonify({"error": "Not found"}), 404
    single_schema = _SchemaClass()
    return jsonify({"item": single_schema.dump(item)}), 200
APIVEOF
echo "  Created public API with PublicSchema"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()
content = content.replace(
    'from inventory_admin import inventory_admin_blue',
    'from inventory_admin import inventory_admin_blue\nfrom api_public import api_blue'
)
content = content.replace(
    'app.register_blueprint(inventory_admin_blue)',
    'app.register_blueprint(inventory_admin_blue)\napp.register_blueprint(api_blue)'
)
with open('app.py', 'w') as f:
    f.write(content)
print('  Registered API blueprint')
"

echo "Stage 2 complete."
