#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

BASE="15Flask/day04"
mkdir -p "$BASE/cart_options"

# --- requirements.txt ---
cat > "$BASE/requirements.txt" << 'EOF'
flask==3.0.0
flask-sqlalchemy==3.1.1
EOF

# --- Dockerfile ---
cat > "$BASE/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5205
CMD ["python", "app.py"]
EOF

# --- models.py ---
cat > "$BASE/models.py" << 'PYEOF'
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class CartItem(db.Model):
    __tablename__ = "cart_items"

    id = db.Column(db.Integer, primary_key=True)
    product_name = db.Column(db.String(200), nullable=False)
    quantity = db.Column(db.Integer, nullable=False, default=1)
    price = db.Column(db.Float, nullable=False)
    options = db.Column(db.JSON, nullable=False, default=dict)

    def __repr__(self):
        return f"<CartItem {self.product_name}>"
PYEOF

# --- cart_options/__init__.py ---
cat > "$BASE/cart_options/__init__.py" << 'PYEOF'
from flask import Blueprint

cart_options_bp = Blueprint("cart_options", __name__)

from . import views  # noqa: E402, F401
PYEOF

# --- cart_options/views.py ---
cat > "$BASE/cart_options/views.py" << 'PYEOF'
from flask import jsonify
from models import db, CartItem
from cart_options import cart_options_bp


@cart_options_bp.route("/api/cart/<int:item_id>/options", methods=["GET"])
def get_options(item_id):
    item = CartItem.query.get_or_404(item_id)
    return jsonify(item.options or {})
PYEOF

# --- app.py (full rewrite) ---
cat > "$BASE/app.py" << 'PYEOF'
import os
from flask import Flask
from models import db, CartItem
from cart_options import cart_options_bp


app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", "sqlite:///shop.db"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)
app.register_blueprint(cart_options_bp)


@app.route("/")
def index():
    return {"status": "ok", "app": "flask-shop"}


def seed():
    """Seed test cart items if the table is empty."""
    if CartItem.query.count() == 0:
        items = [
            CartItem(
                product_name="Wireless Mouse",
                quantity=1,
                price=29.99,
                options={},
            ),
            CartItem(
                product_name="USB-C Hub",
                quantity=1,
                price=49.99,
                options={},
            ),
        ]
        for item in items:
            db.session.add(item)
        db.session.commit()


with app.app_context():
    db.create_all()
    seed()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5205, debug=False)
PYEOF

echo "Stage 1: CartItem model + GET /api/cart/<id>/options + seed items"
