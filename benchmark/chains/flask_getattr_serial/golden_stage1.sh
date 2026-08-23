#!/bin/bash
# Stage 1: Add Product model with internal fields + public listing (FEAT-570)
# Creates models.py with Product model (including internal fields),
# a products blueprint with hardcoded safe field list, and admin seed.
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"

# --- Flask deployment infrastructure ---
cat > "$DAY04_DIR/requirements.txt" << 'REQEOF'
flask==3.0.0
flask-sqlalchemy==3.1.1
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

echo "Stage 1: Adding Product model and public listing (FEAT-570)..."

# Create models.py with Product model
cat > models.py << 'MODEOF'
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Product(db.Model):
    __tablename__ = "products"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(128), nullable=False)
    price = db.Column(db.Float, nullable=False)
    stock = db.Column(db.Integer, default=0)
    cost_price = db.Column(db.Float)
    supplier_notes = db.Column(db.Text)
    margin_pct = db.Column(db.Float)
MODEOF
echo "  Created models.py with Product model"

# Create products blueprint
mkdir -p products
cat > products/__init__.py << 'PRODEOF'
from flask import Blueprint

products_blue = Blueprint('products', __name__, url_prefix='/products')

from . import views
PRODEOF

cat > products/views.py << 'PRODVEOF'
from flask import jsonify, request

from models import db, Product
from . import products_blue


@products_blue.route('/admin/seed', methods=['GET'])
def seed_products():
    existing = Product.query.count()
    if existing > 0:
        return jsonify({"message": f"Already seeded ({existing} products)"}), 200

    samples = [
        Product(name="Wireless Mouse", price=29.99, stock=150,
                cost_price=8.50,
                supplier_notes="Bulk order from Shenzhen Tech Co, MOQ 500",
                margin_pct=71.7),
        Product(name="USB-C Cable", price=12.99, stock=500,
                cost_price=1.20,
                supplier_notes="Supplier: CableCo Ltd, net-30 terms",
                margin_pct=90.8),
        Product(name="Laptop Stand", price=49.99, stock=75,
                cost_price=15.00,
                supplier_notes="Dropship from AluFab, 3-day lead time",
                margin_pct=70.0),
    ]

    for p in samples:
        db.session.add(p)
    db.session.commit()
    return jsonify({"message": f"Seeded {len(samples)} products"}), 201


@products_blue.route('/', methods=['GET'])
def list_products():
    products = Product.query.all()
    # Hardcoded field list — only return public fields
    return jsonify([{
        "id": p.id,
        "name": p.name,
        "price": p.price,
        "stock": p.stock,
    } for p in products]), 200
PRODVEOF
echo "  Created products blueprint with hardcoded safe serialization"

# Update app.py to include models and products blueprint
cat > app.py << 'APPEOF'
from flask import Flask

from models import db
from cart import cart_blue
from demo import demo4
from products import products_blue

app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

app.register_blueprint(demo4.order_blue)
app.register_blueprint(cart_blue)
app.register_blueprint(products_blue)


@app.route('/')
def index():
    return 'index'


@app.route('/list')
def list():
    return 'list'


@app.route('/detail')
def detail():
    return 'detail'


with app.app_context():
    db.create_all()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPEOF
echo "  Updated app.py with database config and products blueprint"

echo "Stage 1 complete."
