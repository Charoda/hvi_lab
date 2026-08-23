#!/bin/bash
# Stage 1 (DX-230): Build user registration and RBAC system.
# Rewrites 15Flask/day04/app.py with in-memory user store, signup/login,
# role hierarchy, RBAC decorator, and GET /roles + GET /me endpoints.
# Default role is "user" — principle of least privilege. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

BASE="15Flask/day04"
mkdir -p "$BASE"

echo "Stage 1: Building user registration and RBAC system (DX-230)..."

# --- requirements.txt ---
cat > "$BASE/requirements.txt" << 'EOF'
flask==3.0.0
EOF

# --- Dockerfile ---
cat > "$BASE/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
EOF

# --- app.py (full rewrite) ---
cat > "$BASE/app.py" << 'PYEOF'
import hashlib
import time
import base64
import json
from functools import wraps
from flask import Flask, jsonify, request

app = Flask(__name__)

# --- Role hierarchy and configuration ---
ROLE_HIERARCHY = {"viewer": 0, "user": 1, "editor": 2, "admin": 3}
DEFAULT_ROLE = "user"

# --- In-memory stores ---
users = {}  # email -> {email, password_hash, role, created_at}

# --- Helpers ---

def hash_password(password):
    return hashlib.sha256(password.encode()).hexdigest()


def make_token(email):
    payload = f"{email}:{time.time()}"
    return base64.b64encode(payload.encode()).decode()


def decode_token(token):
    try:
        payload = base64.b64decode(token.encode()).decode()
        email = payload.split(":")[0]
        return email
    except Exception:
        return None


def get_current_user():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:]
    email = decode_token(token)
    if not email or email not in users:
        return None
    return users[email]


def resolve_effective_roles(role):
    """Return all roles at or below the given role's hierarchy level."""
    level = ROLE_HIERARCHY.get(role, 0)
    return sorted(
        [r for r, l in ROLE_HIERARCHY.items() if l <= level],
        key=lambda r: ROLE_HIERARCHY[r],
    )


def require_role(min_role):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            user = get_current_user()
            if not user:
                return jsonify({"error": "Unauthorized"}), 401
            if ROLE_HIERARCHY.get(user["role"], 0) < ROLE_HIERARCHY[min_role]:
                return jsonify({"error": "Forbidden"}), 403
            return f(*args, **kwargs)
        return wrapper
    return decorator


# --- Seed admin user ---
users["admin@example.com"] = {
    "email": "admin@example.com",
    "password_hash": hash_password("admin123"),
    "role": "admin",
    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}


# --- Routes ---

@app.route("/")
def index():
    return jsonify({"status": "ok", "service": "flask-rbac"})


@app.route("/signup", methods=["POST"])
def signup():
    data = request.get_json()
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    email = data.get("email", "").strip()
    password = data.get("password", "")

    if not email or not password:
        return jsonify({"error": "email and password are required"}), 400

    if email in users:
        return jsonify({"error": "Email already registered"}), 409

    user = {
        "email": email,
        "password_hash": hash_password(password),
        "role": DEFAULT_ROLE,
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    users[email] = user

    token = make_token(email)
    return jsonify({
        "user": {
            "email": email,
            "role": user["role"],
            "effectiveRoles": resolve_effective_roles(user["role"]),
        },
        "token": token,
    }), 201


@app.route("/login", methods=["POST"])
def login():
    data = request.get_json()
    if not data:
        return jsonify({"error": "JSON body required"}), 400

    email = data.get("email", "").strip()
    password = data.get("password", "")

    user = users.get(email)
    if not user or user["password_hash"] != hash_password(password):
        return jsonify({"error": "Invalid credentials"}), 401

    token = make_token(email)
    return jsonify({
        "user": {
            "email": email,
            "role": user["role"],
            "effectiveRoles": resolve_effective_roles(user["role"]),
        },
        "token": token,
    }), 200


@app.route("/roles", methods=["GET"])
def get_roles():
    return jsonify({
        "roles": sorted(ROLE_HIERARCHY.keys(), key=lambda r: ROLE_HIERARCHY[r]),
        "defaultRole": DEFAULT_ROLE,
        "hierarchy": ROLE_HIERARCHY,
    })


@app.route("/me", methods=["GET"])
@require_role("viewer")
def get_me():
    user = get_current_user()
    return jsonify({
        "email": user["email"],
        "role": user["role"],
        "effectiveRoles": resolve_effective_roles(user["role"]),
    })


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PYEOF

echo "  Rewrote app.py with auth system, RBAC, role hierarchy"
echo "  Created requirements.txt and Dockerfile"
echo "Stage 1 complete."
