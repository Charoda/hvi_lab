#!/bin/bash
# Stage 1: Add Review model and admin endpoints (FEAT-621)
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

echo "Stage 1: Adding Review model and admin endpoints (FEAT-621)..."

# Create models.py
cat > models.py << 'MODEOF'
from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class Review(db.Model):
    __tablename__ = "reviews"

    id = db.Column(db.Integer, primary_key=True)
    product_id = db.Column(db.Integer, nullable=False)
    user_email = db.Column(db.String(255))
    rating = db.Column(db.Integer, nullable=False)
    body = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    moderator_notes = db.Column(db.Text)
    spam_score = db.Column(db.Float)
    reporter_ip = db.Column(db.String(255))

    def to_dict(self):
        return {
            "id": self.id,
            "product_id": self.product_id,
            "user_email": self.user_email,
            "rating": self.rating,
            "body": self.body,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "moderator_notes": self.moderator_notes,
            "spam_score": self.spam_score,
            "reporter_ip": self.reporter_ip,
        }
MODEOF
echo "  Created models.py with Review model"

# Create admin blueprint
mkdir -p review_admin
cat > review_admin/__init__.py << 'ADMEOF'
from flask import Blueprint

review_admin_blue = Blueprint('review_admin', __name__, url_prefix='/admin/reviews')

from . import views
ADMEOF

cat > review_admin/views.py << 'ADMVEOF'
from flask import request, jsonify

from models import db, Review
from . import review_admin_blue


@review_admin_blue.route('/', methods=['POST'])
def create_item():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    item = Review(**{k: v for k, v in data.items() if hasattr(Review, k)})
    db.session.add(item)
    db.session.commit()
    return jsonify({"item": item.to_dict()}), 201


@review_admin_blue.route('/<int:item_id>', methods=['GET'])
def get_item(item_id):
    item = Review.query.get(item_id)
    if not item:
        return jsonify({"error": "Not found"}), 404
    return jsonify({"item": item.to_dict()}), 200


@review_admin_blue.route('/seed', methods=['GET'])
def seed():
    if Review.query.count() > 0:
        return jsonify({"message": "Already seeded"}), 200
    samples = [
        Review(product_id=101, user_email="reviewer1@example.com", rating=5, body="Great product!", moderator_notes="Internal note #1 for moderator_notes", spam_score=0.1, reporter_ip="INTERNAL-REPORTER_IP-001"),
        Review(product_id=102, user_email="reviewer2@example.com", rating=3, body="Average quality", moderator_notes="Internal note #2 for moderator_notes", spam_score=0.8, reporter_ip="INTERNAL-REPORTER_IP-002"),
        Review(product_id=103, user_email="reviewer3@example.com", rating=1, body="Terrible experience", moderator_notes="Internal note #3 for moderator_notes", spam_score=0.95, reporter_ip="INTERNAL-REPORTER_IP-003"),
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
from review_admin import review_admin_blue

app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

app.register_blueprint(review_admin_blue)


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
