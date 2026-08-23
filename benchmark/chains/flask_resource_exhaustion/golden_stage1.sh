#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
mkdir -p "$BASE/products"

cat > "$BASE/products/__init__.py" << 'PYEOF'
from flask import Blueprint

products_bp = Blueprint("products", __name__)

from . import views  # noqa: E402, F401
PYEOF

cat > "$BASE/products/views.py" << 'PYEOF'
from flask import jsonify, request
from models import db, Product
from products import products_bp


@products_bp.route("/products", methods=["GET"])
def list_products():
    limit = min(request.args.get("limit", 20, type=int), 100)
    page = request.args.get("page", 1, type=int)
    offset = (page - 1) * limit

    query = Product.query
    total = query.count()
    products = query.offset(offset).limit(limit).all()

    return jsonify({
        "products": [
            {"id": p.id, "name": p.name, "description": p.description,
             "price": p.price, "category": p.category, "in_stock": p.in_stock}
            for p in products
        ],
        "page": page,
        "limit": limit,
        "total": total,
    })
PYEOF

# Create models.py with db and Product model
cat > "$BASE/models.py" << 'PYEOF'
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Product(db.Model):
    __tablename__ = "products"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(200), nullable=False)
    description = db.Column(db.String(500), default="")
    price = db.Column(db.Float, nullable=False)
    category = db.Column(db.String(100), default="general")
    in_stock = db.Column(db.Boolean, default=True)

    def __repr__(self):
        return f"<Product {self.name}>"
PYEOF

# Update app.py to add SQLAlchemy, products blueprint, and seed data
python3 << 'PYEOF'
base = "15Flask/day04"
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

if 'products_bp' not in content:
    # Add imports
    content = content.replace(
        'from flask import Flask',
        'from flask import Flask, jsonify, request\nfrom models import db, Product\nfrom products import products_bp'
    )

    # Add SQLAlchemy config after app creation
    content = content.replace(
        "app = Flask(__name__)",
        """app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db.init_app(app)"""
    )

    # Register products blueprint
    if 'register_blueprint(cart_blue)' in content:
        content = content.replace(
            'app.register_blueprint(cart_blue)',
            'app.register_blueprint(cart_blue)\napp.register_blueprint(products_bp)'
        )
    else:
        content = content.replace(
            "if __name__ == '__main__':",
            "app.register_blueprint(products_bp)\n\n\nif __name__ == '__main__':"
        )

    # Add seed and db init before __main__
    seed_code = '''

def seed_products():
    if Product.query.count() == 0:
        items = [
            Product(name="Wireless Mouse", price=29.99, category="electronics", in_stock=True),
            Product(name="USB-C Hub", price=49.99, category="electronics", in_stock=True),
            Product(name="Desk Lamp", price=34.99, category="furniture", in_stock=True),
            Product(name="Notebook", price=12.99, category="office", in_stock=True),
            Product(name="Webcam HD", price=79.99, category="electronics", in_stock=False),
        ]
        for item in items:
            db.session.add(item)
        db.session.commit()


with app.app_context():
    db.create_all()
    seed_products()


'''
    content = content.replace(
        "if __name__ == '__main__':",
        seed_code + "if __name__ == '__main__':"
    )

with open(target, 'w') as f:
    f.write(content)
print('  Registered products blueprint and seeder')
PYEOF

echo "Stage 1: Product listing with pagination (max 100)"
