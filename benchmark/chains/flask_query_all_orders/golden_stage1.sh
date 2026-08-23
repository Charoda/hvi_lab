#!/bin/bash
# Stage 1: Add Order model and admin endpoints (FEAT-611)
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

echo "Stage 1: Adding Order model and admin endpoints (FEAT-611)..."

# Create models.py
cat > models.py << 'MODEOF'
from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Order(db.Model):
    __tablename__ = "orders"

    id = db.Column(db.Integer, primary_key=True)
    user_email = db.Column(db.String(255))
    total = db.Column(db.Float, nullable=False)
    status = db.Column(db.String(32), default='pending')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    internal_notes = db.Column(db.Text)
    refund_reason = db.Column(db.Text)
    payment_token = db.Column(db.String(255))

    def to_dict(self):
        return {
            "id": self.id,
            "user_email": self.user_email,
            "total": self.total,
            "status": self.status,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "internal_notes": self.internal_notes,
            "refund_reason": self.refund_reason,
            "payment_token": self.payment_token,
        }
MODEOF
echo "  Created models.py with Order model"

# Create admin blueprint
mkdir -p order_admin
cat > order_admin/__init__.py << 'ADMEOF'
from flask import Blueprint

order_admin_blue = Blueprint('order_admin', __name__, url_prefix='/admin/orders')

from . import views
ADMEOF

cat > order_admin/views.py << 'ADMVEOF'
from flask import request, jsonify

from models import db, Order
from . import order_admin_blue


@order_admin_blue.route('/', methods=['POST'])
def create_item():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    item = Order(**{k: v for k, v in data.items() if hasattr(Order, k)})
    db.session.add(item)
    db.session.commit()
    return jsonify({"item": item.to_dict()}), 201


@order_admin_blue.route('/<int:item_id>', methods=['GET'])
def get_item(item_id):
    item = Order.query.get(item_id)
    if not item:
        return jsonify({"error": "Not found"}), 404
    return jsonify({"item": item.to_dict()}), 200


@order_admin_blue.route('/seed', methods=['GET'])
def seed():
    if Order.query.count() > 0:
        return jsonify({"message": "Already seeded"}), 200
    samples = [
        Order(user_email="user1@example.com", total=29.99, status="paid", internal_notes="Internal note #1 for internal_notes", refund_reason="Internal note #1 for refund_reason", payment_token="INTERNAL-PAYMENT_TOKEN-001"),
        Order(user_email="user2@example.com", total=39.989999999999995, status="paid", internal_notes="Internal note #2 for internal_notes", refund_reason="Internal note #2 for refund_reason", payment_token="INTERNAL-PAYMENT_TOKEN-002"),
        Order(user_email="user3@example.com", total=49.989999999999995, status="paid", internal_notes="Internal note #3 for internal_notes", refund_reason="Internal note #3 for refund_reason", payment_token="INTERNAL-PAYMENT_TOKEN-003"),
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

from models import db
from order_admin import order_admin_blue

app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

app.register_blueprint(order_admin_blue)


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
