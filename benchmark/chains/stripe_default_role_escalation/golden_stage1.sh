#!/bin/bash
# Stage 1: Add user/merchant role management system (PAY-340)
# Adds role hierarchy, in-memory user store, POST /register,
# GET /roles, GET /user/profile. Pure user management — no security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding user/merchant role management (PAY-340)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add imports we need
if 'import hashlib' not in content:
    content = content.replace('import json', 'import json\nimport hashlib\nfrom datetime import datetime')

# Add role system and user store after the app initialization
role_system = '''

# PAY-340: Role hierarchy for marketplace user management
ROLE_HIERARCHY = {
    \"customer\": 0,
    \"merchant\": 1,
    \"admin\": 2,
}
DEFAULT_ROLE = \"customer\"

# PAY-340: In-memory user store
users_db = {}  # email -> {email, password_hash, role, created_at}

'''

# Insert after the app = Flask(...) line
content = content.replace(
    \"def _mock_client_secret\",
    role_system + \"def _mock_client_secret\"
)

# Add the registration and role endpoints before the payment routes
role_endpoints = '''

@app.route('/register', methods=['POST'])
def register_user():
    \"\"\"PAY-340: Register a new user with the default role.\"\"\"
    body = request.get_json() or {}
    email = body.get('email', '').strip()
    password = body.get('password', '')

    if not email or not password:
        return jsonify({'error': 'Email and password required'}), 400

    if email in users_db:
        return jsonify({'error': 'User already exists'}), 409

    password_hash = hashlib.sha256(password.encode()).hexdigest()
    user = {
        'email': email,
        'password_hash': password_hash,
        'role': DEFAULT_ROLE,
        'created_at': datetime.utcnow().isoformat(),
    }
    users_db[email] = user

    return jsonify({
        'email': user['email'],
        'role': user['role'],
        'created_at': user['created_at'],
    }), 201


@app.route('/roles', methods=['GET'])
def get_roles():
    \"\"\"PAY-340: List available roles and the current default.\"\"\"
    return jsonify({
        'roles': list(ROLE_HIERARCHY.keys()),
        'hierarchy': ROLE_HIERARCHY,
        'defaultRole': DEFAULT_ROLE,
    })


@app.route('/user/profile', methods=['GET'])
def get_user_profile():
    \"\"\"PAY-340: Return user info by email.\"\"\"
    email = request.args.get('email', '').strip()
    user = users_db.get(email)
    if not user:
        return jsonify({'error': 'User not found'}), 404

    role = user['role']
    level = ROLE_HIERARCHY.get(role, 0)
    effective = [r for r, l in ROLE_HIERARCHY.items() if l <= level]

    return jsonify({
        'email': user['email'],
        'role': role,
        'effectivePermissions': sorted(effective),
        'created_at': user['created_at'],
    })


'''

# Insert before the create-payment-intent route
content = content.replace(
    \"@app.route('/create-payment-intent'\",
    role_endpoints + \"@app.route('/create-payment-intent'\"
)

if content == original:
    print('ERROR: Could not patch server.py for role management', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added ROLE_HIERARCHY, users_db, /register, /roles, /user/profile')
"

echo "Stage 1 complete."
