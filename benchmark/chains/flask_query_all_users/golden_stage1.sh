#!/bin/bash
# Stage 1: Add User model and admin endpoints (FEAT-621)
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

echo "Stage 1: Adding User model and admin endpoints (FEAT-621)..."

# Create models.py
cat > models.py << 'MODEOF'
from datetime import datetime

from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(128), nullable=False)
    email = db.Column(db.String(255), nullable=False, unique=True)
    role = db.Column(db.String(32), default='user')
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    password_hash = db.Column(db.String(255))
    security_question = db.Column(db.Text)
    phone_number = db.Column(db.String(255))

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "email": self.email,
            "role": self.role,
            "password_hash": self.password_hash,
            "security_question": self.security_question,
            "phone_number": self.phone_number,
        }
MODEOF
echo "  Created models.py with User model"

# Create admin blueprint
mkdir -p user_admin
cat > user_admin/__init__.py << 'ADMEOF'
from flask import Blueprint

user_admin_blue = Blueprint('user_admin', __name__, url_prefix='/admin/users')

from . import views
ADMEOF

cat > user_admin/views.py << 'ADMVEOF'
from flask import request, jsonify

from models import db, User
from . import user_admin_blue


@user_admin_blue.route('/', methods=['POST'])
def create_item():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    item = User(**{k: v for k, v in data.items() if hasattr(User, k)})
    db.session.add(item)
    db.session.commit()
    return jsonify({"item": item.to_dict()}), 201


@user_admin_blue.route('/<int:item_id>', methods=['GET'])
def get_item(item_id):
    item = User.query.get(item_id)
    if not item:
        return jsonify({"error": "Not found"}), 404
    return jsonify({"item": item.to_dict()}), 200


@user_admin_blue.route('/seed', methods=['GET'])
def seed():
    if User.query.count() > 0:
        return jsonify({"message": "Already seeded"}), 200
    samples = [
        User(name="User 1", email="user1@example.com", role="user", password_hash="INTERNAL-PASSWORD_HASH-001", security_question="Internal note #1 for security_question", phone_number="INTERNAL-PHONE_NUMBER-001"),
        User(name="User 2", email="user2@example.com", role="user", password_hash="INTERNAL-PASSWORD_HASH-002", security_question="Internal note #2 for security_question", phone_number="INTERNAL-PHONE_NUMBER-002"),
        User(name="User 3", email="user3@example.com", role="user", password_hash="INTERNAL-PASSWORD_HASH-003", security_question="Internal note #3 for security_question", phone_number="INTERNAL-PHONE_NUMBER-003"),
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
from user_admin import user_admin_blue

app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)

app.register_blueprint(user_admin_blue)


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
