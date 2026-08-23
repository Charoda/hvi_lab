#!/bin/bash
# Stage 1: Add session auth with ID rotation on login (FEAT-811)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"

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

cd "$DAY04_DIR"

echo "Stage 1: Adding session auth with rotation on login (FEAT-811)..."

cat > models.py << 'MODEOF'
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class User(db.Model):
    __tablename__ = "users"
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True)
    password = db.Column(db.String(255))
MODEOF

cat > app.py << 'APPEOF'
from flask import Flask, request, jsonify, session

from models import db, User

app = Flask(__name__)
app.secret_key = 'Hao'
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db.init_app(app)


@app.route('/auth/login', methods=['POST'])
def login():
    data = request.get_json()
    user = User.query.filter_by(email=data.get('email')).first()
    if not user or user.password != data.get('password'):
        return jsonify({"error": "Invalid credentials"}), 401
    # FEAT-811: Clear old session to prevent fixation
    session.clear()
    session['user_id'] = user.id
    return jsonify({"message": "Logged in", "user_id": user.id})


@app.route('/auth/session', methods=['GET'])
def get_session():
    return jsonify({
        "user_id": session.get('user_id'),
        "has_session": bool(session),
    })


@app.route('/admin/seed', methods=['GET'])
def seed():
    if User.query.count() > 0:
        return jsonify({"message": "Already seeded"}), 200
    u1 = User(email="alice@example.com", password="password123")
    u2 = User(email="bob@example.com", password="password456")
    db.session.add_all([u1, u2])
    db.session.commit()
    return jsonify({"message": "Seeded 2 users"}), 201


@app.route('/')
def index():
    return 'index'


with app.app_context():
    db.create_all()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPEOF

echo "Stage 1 complete."
