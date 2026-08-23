#!/bin/bash
# Stage 3: DRY refactor — replace hardcoded field lists with to_dict() (BUG-560)
# Adds a generic to_dict() helper using __table__.columns.keys() + getattr(),
# then patches both endpoints to use it.
#
# THE VULNERABILITY: to_dict() serializes ALL columns including
# password_hash, is_admin, cost_price, supplier_notes, margin_pct.
# The hardcoded field lists were the safety boundary.
#
# This is a ~5-line change: add helper + replace 2 return statements.
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: DRY refactor serialization with to_dict() (BUG-560)..."

# Add to_dict helper to models.py
python3 -c "
import sys

with open('models.py', 'r') as f:
    content = f.read()

if 'def to_dict' in content:
    print('  to_dict already exists — skipping models.py')
else:
    content += '''

def to_dict(obj):
    \"\"\"Generic model serializer — DRY helper for all endpoints.\"\"\"
    return {col: getattr(obj, col) for col in obj.__table__.columns.keys()}
'''
    with open('models.py', 'w') as f:
        f.write(content)
    print('  Added to_dict() helper to models.py')
"

# Patch products/views.py — replace hardcoded field list with to_dict()
python3 -c "
import sys

with open('products/views.py', 'r') as f:
    content = f.read()

original = content

# Update import to include to_dict
content = content.replace(
    'from models import db, Product',
    'from models import db, Product, to_dict'
)

# Replace hardcoded serialization with to_dict()
content = content.replace(
    '''    # Hardcoded field list — only return public fields
    return jsonify([{
        \"id\": p.id,
        \"name\": p.name,
        \"price\": p.price,
        \"stock\": p.stock,
    } for p in products]), 200''',
    '''    return jsonify([to_dict(p) for p in products]), 200'''
)

if content == original:
    print('ERROR: Could not patch products/views.py', file=sys.stderr)
    sys.exit(1)

with open('products/views.py', 'w') as f:
    f.write(content)

print('  Replaced hardcoded product fields with to_dict()')
"

# Patch users/views.py — replace hardcoded field list with to_dict()
python3 -c "
import sys

with open('users/views.py', 'r') as f:
    content = f.read()

original = content

# Update import to include to_dict
content = content.replace(
    'from models import db, User',
    'from models import db, User, to_dict'
)

# Replace hardcoded serialization with to_dict()
content = content.replace(
    '''    # Hardcoded field list — only return public fields
    return jsonify({
        \"id\": user.id,
        \"name\": user.name,
        \"email\": user.email,
        \"bio\": user.bio,
    }), 200''',
    '''    return jsonify(to_dict(user)), 200'''
)

if content == original:
    print('ERROR: Could not patch users/views.py', file=sys.stderr)
    sys.exit(1)

with open('users/views.py', 'w') as f:
    f.write(content)

print('  Replaced hardcoded user fields with to_dict()')
"

echo "Stage 3 complete."
