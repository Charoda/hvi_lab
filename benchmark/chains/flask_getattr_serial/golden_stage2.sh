#!/bin/bash
# Stage 2: Add User model with profile endpoint (FEAT-571)
# Adds User model to models.py and a users blueprint with
# hardcoded safe field list (same pattern as products).
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding User model and profile endpoint (FEAT-571)..."

# Append User model to models.py
python3 -c "
import sys

with open('models.py', 'r') as f:
    content = f.read()

if 'class User' in content:
    print('  User model already exists — skipping')
    sys.exit(0)

user_model = '''

class User(db.Model):
    __tablename__ = \"users\"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(128), nullable=False)
    email = db.Column(db.String(256), unique=True, nullable=False)
    password_hash = db.Column(db.String(256))
    is_admin = db.Column(db.Boolean, default=False)
    bio = db.Column(db.Text)
'''

with open('models.py', 'a') as f:
    f.write(user_model)

print('  Added User model to models.py')
"

# Create users blueprint
mkdir -p users
cat > users/__init__.py << 'USREOF'
from flask import Blueprint

users_blue = Blueprint('users', __name__, url_prefix='/users')

from . import views
USREOF

cat > users/views.py << 'USRVEOF'
from flask import jsonify

from models import db, User
from . import users_blue


@users_blue.route('/seed', methods=['GET'])
def seed_users():
    existing = User.query.count()
    if existing > 0:
        return jsonify({"message": f"Already seeded ({existing} users)"}), 200

    try:
        from werkzeug.security import generate_password_hash
        hash_fn = generate_password_hash
    except ImportError:
        import hashlib
        hash_fn = lambda pw: hashlib.sha256(pw.encode()).hexdigest()

    samples = [
        User(name="Alice Admin", email="alice@example.com",
             password_hash=hash_fn("supersecret123"),
             is_admin=True, bio="Platform administrator"),
        User(name="Bob User", email="bob@example.com",
             password_hash=hash_fn("bobpassword456"),
             is_admin=False, bio="Regular user who loves gadgets"),
        User(name="Carol Tester", email="carol@example.com",
             password_hash=hash_fn("carolpass789"),
             is_admin=False, bio="QA engineer"),
    ]

    for u in samples:
        db.session.add(u)
    db.session.commit()
    return jsonify({"message": f"Seeded {len(samples)} users"}), 201


@users_blue.route('/<int:user_id>', methods=['GET'])
def get_user(user_id):
    user = User.query.get(user_id)
    if not user:
        return jsonify({"error": "User not found"}), 404
    # Hardcoded field list — only return public fields
    return jsonify({
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "bio": user.bio,
    }), 200
USRVEOF
echo "  Created users blueprint with hardcoded safe serialization"

# Register users blueprint in app.py
python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

original = content

content = content.replace(
    'from products import products_blue',
    'from products import products_blue\nfrom users import users_blue'
)

content = content.replace(
    'app.register_blueprint(products_blue)',
    'app.register_blueprint(products_blue)\napp.register_blueprint(users_blue)'
)

if content == original:
    print('ERROR: Could not patch app.py', file=sys.stderr)
    sys.exit(1)

with open('app.py', 'w') as f:
    f.write(content)

print('  Registered users blueprint in app.py')
"

echo "Stage 2 complete."
