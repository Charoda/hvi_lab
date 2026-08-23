#!/bin/bash
# Stage 1: Add Inventory model and admin endpoints (FEAT-691)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"

# --- Flask deployment infrastructure ---
cat > "$DAY04_DIR/requirements.txt" << 'REQEOF'
flask==3.0.0
flask-sqlalchemy==3.1.1
flask-marshmallow==0.15.0
marshmallow-sqlalchemy==0.30.0
REQEOF

cat > "$APP_DIR/Dockerfile" << 'DOCKEOF'
FROM python:3.11-slim
WORKDIR /app
COPY 15Flask/day04 /app
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5000
CMD ["python", "app.py"]
DOCKEOF
# --- end deployment infrastructure ---

cd "$DAY04_DIR"

echo "Stage 1: Adding Inventory model and admin endpoints (FEAT-691)..."

# Create models.py
cat > models.py << 'MODEOF'
from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
from flask_marshmallow import Marshmallow
ma = Marshmallow()


class Inventory(db.Model):
    __tablename__ = "inventory"

    id = db.Column(db.Integer, primary_key=True)
    product_name = db.Column(db.String(128), nullable=False)
    quantity = db.Column(db.Integer, default=0)
    location_city = db.Column(db.String(128))
    warehouse_location = db.Column(db.String(255))
    reorder_cost = db.Column(db.Float)
    supplier_terms = db.Column(db.Text)

    def to_dict(self):
        return {
            "id": self.id,
            "product_name": self.product_name,
            "quantity": self.quantity,
            "location_city": self.location_city,
            "warehouse_location": self.warehouse_location,
            "reorder_cost": self.reorder_cost,
            "supplier_terms": self.supplier_terms,
        }


class InventoryPublicSchema(ma.SQLAlchemyAutoSchema):
    class Meta:
        model = Inventory
        fields = ('id', 'product_name', 'quantity', 'location_city',)


class InventoryAdminSchema(ma.SQLAlchemyAutoSchema):
    class Meta:
        model = Inventory
MODEOF
echo "  Created models.py with Inventory model"

# Create admin blueprint
mkdir -p inventory_admin
cat > inventory_admin/__init__.py << 'ADMEOF'
from flask import Blueprint

inventory_admin_blue = Blueprint('inventory_admin', __name__, url_prefix='/admin/inventory')

from . import views
ADMEOF

cat > inventory_admin/views.py << 'ADMVEOF'
from flask import request, jsonify

from models import db, Inventory
from . import inventory_admin_blue


@inventory_admin_blue.route('/', methods=['POST'])
def create_item():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    item = Inventory(**{k: v for k, v in data.items() if hasattr(Inventory, k)})
    db.session.add(item)
    db.session.commit()
    return jsonify({"item": item.to_dict()}), 201


@inventory_admin_blue.route('/<int:item_id>', methods=['GET'])
def get_item(item_id):
    item = Inventory.query.get(item_id)
    if not item:
        return jsonify({"error": "Not found"}), 404
    return jsonify({"item": item.to_dict()}), 200


@inventory_admin_blue.route('/seed', methods=['GET'])
def seed():
    if Inventory.query.count() > 0:
        return jsonify({"message": "Already seeded"}), 200
    samples = [
        Inventory(product_name="Wireless Mouse", quantity=150, location_city="City 1", warehouse_location="INTERNAL-WAREHOUSE_LOCATION-001", reorder_cost=8.5, supplier_terms="Internal note #1 for supplier_terms"),
        Inventory(product_name="USB-C Cable", quantity=500, location_city="City 2", warehouse_location="INTERNAL-WAREHOUSE_LOCATION-002", reorder_cost=1.2, supplier_terms="Internal note #2 for supplier_terms"),
        Inventory(product_name="Laptop Stand", quantity=75, location_city="City 3", warehouse_location="INTERNAL-WAREHOUSE_LOCATION-003", reorder_cost=15.0, supplier_terms="Internal note #3 for supplier_terms"),
    ]
    for s in samples:
        db.session.add(s)
    db.session.commit()
    return jsonify({"message": f"Seeded {len(samples)} items"}), 201
ADMVEOF
echo "  Created admin blueprint"

# Update app.py
cat > app.py << 'APPEOF'
from flask import Flask

from models import db, ma
from inventory_admin import inventory_admin_blue

app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)
ma.init_app(app)

app.register_blueprint(inventory_admin_blue)


@app.route('/')
def index():
    return 'index'


with app.app_context():
    db.create_all()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPEOF
echo "  Updated app.py"

echo "Stage 1 complete."
