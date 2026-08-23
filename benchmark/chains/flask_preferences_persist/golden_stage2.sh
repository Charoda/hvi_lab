#!/usr/bin/env bash
# Stage 2: Add PUT /api/user/preferences with dict.update merge (FEAT-751)
# BUG: changes don't persist — SQLAlchemy can't detect JSON mutations.
# The endpoint returns the merged dict but it never reaches the database.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding PUT /api/user/preferences endpoint (FEAT-751)..."

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

if ! grep -q "update_user_preferences" "$APP_FILE" 2>/dev/null; then
    cat >> "$APP_FILE" <<'ROUTES2'


@app.route('/api/user/preferences', methods=['PUT'])
def update_user_preferences():
    user_id = session.get('user_id')
    if not user_id:
        return jsonify({'error': 'Not logged in'}), 401
    user = User.query.get(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404
    data = request.get_json()
    if not data:
        return jsonify({'error': 'Invalid JSON'}), 400
    if user.preferences is None:
        user.preferences = {}
    user.preferences.update(data)
    db.session.commit()
    return jsonify(user.preferences)

ROUTES2
    echo "  Added PUT /api/user/preferences endpoint"
fi

echo "Stage 2 complete."
