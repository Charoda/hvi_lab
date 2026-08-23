#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

BASE="15Flask/day04"
mkdir -p "$BASE/user_prefs"

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


class UserPrefs(db.Model):
    __tablename__ = "user_prefs"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    preferences = db.Column(db.JSON, nullable=False, default=dict)

    def __repr__(self):
        return f"<UserPrefs {self.username}>"
PYEOF

# --- user_prefs/__init__.py ---
cat > "$BASE/user_prefs/__init__.py" << 'PYEOF'
from flask import Blueprint

user_prefs_bp = Blueprint("user_prefs", __name__)

from . import views  # noqa: E402, F401
PYEOF

# --- user_prefs/views.py ---
cat > "$BASE/user_prefs/views.py" << 'PYEOF'
from flask import jsonify
from models import db, UserPrefs
from user_prefs import user_prefs_bp


@user_prefs_bp.route("/api/user/<int:user_id>/preferences", methods=["GET"])
def get_preferences(user_id):
    user = UserPrefs.query.get_or_404(user_id)
    return jsonify(user.preferences or {})
PYEOF

# --- app.py (full rewrite) ---
cat > "$BASE/app.py" << 'PYEOF'
import os
from flask import Flask
from models import db, UserPrefs
from user_prefs import user_prefs_bp


app = Flask(__name__)
app.config["SQLALCHEMY_DATABASE_URI"] = os.environ.get(
    "DATABASE_URL", "sqlite:///shop.db"
)
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db.init_app(app)
app.register_blueprint(user_prefs_bp)


@app.route("/")
def index():
    return {"status": "ok", "app": "flask-shop"}


def seed():
    """Seed a test user if the table is empty."""
    if UserPrefs.query.count() == 0:
        user = UserPrefs(
            username="shopuser",
            email="shop@example.com",
            preferences={},
        )
        db.session.add(user)
        db.session.commit()


with app.app_context():
    db.create_all()
    seed()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5205, debug=False)
PYEOF

echo "Stage 1: UserPrefs model + GET /api/user/<id>/preferences + seed user"
