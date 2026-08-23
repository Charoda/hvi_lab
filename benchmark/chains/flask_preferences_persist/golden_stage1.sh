#!/usr/bin/env bash
# Stage 1: Add preferences JSON column to User model + GET endpoint (FEAT-750)
# Adds db.Column(db.JSON) to User model and GET /api/user/preferences endpoint.
# Pure schema extension + read endpoint — no write path yet.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding preferences JSON column and GET endpoint (FEAT-750)..."

# Find the main app file
APP_FILE="15Flask/day04/app.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/day04/*" -maxdepth 4 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/Flask/*" -maxdepth 4 | tail -1)
fi

if [ -z "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask app file"
    exit 1
fi

echo "  Target app file: $APP_FILE"

# Add preferences column to User model
python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Add preferences column to User model — after the last db.Column line
if 'preferences' not in content or 'preferences = db.Column' not in content:
    user_class = re.search(r'class User\b[^:]*:', content)
    if user_class:
        start = user_class.start()
        next_class = re.search(r'\nclass ', content[start + 1:])
        end = start + 1 + next_class.start() if next_class else len(content)

        user_block = content[start:end]
        col_matches = list(re.finditer(r'(    \w+\s*=\s*db\.Column\([^)]+\))', user_block))
        if col_matches:
            last_col = col_matches[-1]
            insert_pos = start + last_col.end()
            pref_col = "\n    preferences = db.Column(db.JSON, nullable=False, default=dict)"
            content = content[:insert_pos] + pref_col + content[insert_pos:]

with open(app_file, 'w') as f:
    f.write(content)

print("  Added preferences JSON column to User model")
PYEOF

# Ensure SQLAlchemy and session imports + db setup
python3 - "$APP_FILE" <<'DBSETUP'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Add imports
if 'SQLAlchemy' not in content:
    content = "from flask_sqlalchemy import SQLAlchemy\n" + content
if 'jsonify' not in content and 'from flask import' in content:
    content = re.sub(r'from flask import ([^\n]+)',
                     lambda m: 'from flask import ' + m.group(1).rstrip() + ', jsonify, request, session',
                     content, count=1)
elif 'jsonify' not in content:
    content = "from flask import jsonify, request, session\n" + content

# Add db setup after app = Flask(...)
if 'SQLAlchemy(app)' not in content and 'db = ' not in content:
    app_match = re.search(r"(app\s*=\s*Flask\([^)]+\)[^\n]*\n)", content)
    if app_match:
        insert_pos = app_match.end()
        db_setup = (
            "app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///shop.db'\n"
            "app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False\n"
            "app.config['SECRET_KEY'] = 'dev-secret-key-123'\n"
            "db = SQLAlchemy(app)\n\n"
        )
        content = content[:insert_pos] + db_setup + content[insert_pos:]

with open(app_file, 'w') as f:
    f.write(content)

print("  Added SQLAlchemy + session imports and db setup")
DBSETUP

# Add User model + auth endpoints (needed for session-based preferences)
if ! grep -q "class User" "$APP_FILE" 2>/dev/null; then
    cat >> "$APP_FILE" <<'AUTH_ROUTES'


# --- User auth (for preferences feature) ---
from werkzeug.security import generate_password_hash, check_password_hash

class User(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True)
    password_hash = db.Column(db.String(256), nullable=False)
    preferences = db.Column(db.JSON, nullable=False, default=dict)

with app.app_context():
    db.create_all()

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json() or request.form
    username = data.get('username', '')
    password = data.get('password', '')
    email = data.get('email', '')
    if not username or not password:
        return jsonify({'error': 'Missing fields'}), 400
    if User.query.filter_by(username=username).first():
        return jsonify({'error': 'User exists'}), 409
    user = User(username=username, email=email,
                password_hash=generate_password_hash(password))
    db.session.add(user)
    db.session.commit()
    session['user_id'] = user.id
    return jsonify({'id': user.id, 'username': user.username}), 201

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json() or request.form
    username = data.get('username', '')
    password = data.get('password', '')
    user = User.query.filter_by(username=username).first()
    if not user or not check_password_hash(user.password_hash, password):
        return jsonify({'error': 'Invalid credentials'}), 401
    session['user_id'] = user.id
    return jsonify({'id': user.id, 'username': user.username})

AUTH_ROUTES
    echo "  Added User model + auth endpoints"
fi

# Add GET endpoint
if ! grep -q "/api/user/preferences" "$APP_FILE" 2>/dev/null; then
    cat >> "$APP_FILE" <<'ROUTES1'


# --- User preferences endpoints (FEAT-750) ---

@app.route('/api/user/preferences')
def get_user_preferences():
    user_id = session.get('user_id')
    if not user_id:
        return jsonify({'error': 'Not logged in'}), 401
    user = User.query.get(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404
    return jsonify(user.preferences or {})

ROUTES1
    echo "  Added GET /api/user/preferences endpoint"
fi

echo "Stage 1 complete."
