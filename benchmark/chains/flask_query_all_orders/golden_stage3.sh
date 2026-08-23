#!/bin/bash
# Stage 3: Fix order history serialization error (BUG-611)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: Applying vulnerability (BUG-611)..."

python3 -c "
import sys

with open('api_public/views.py', 'r') as f:
    content = f.read()

original = content

content = content.replace(
    '''def _fetch_items(**filters):
    rows = db.session.query(
        Order.id, Order.user_email, Order.total, Order.status, Order.created_at
    ).filter_by(**filters).all()
    return [row._asdict() for row in rows]''',
    '''def _fetch_items(**filters):
    rows = Order.query.filter_by(**filters).all()
    return [row.to_dict() for row in rows]'''
)

if content == original:
    print('ERROR: Could not apply stage 3 patch', file=sys.stderr)
    sys.exit(1)

with open('api_public/views.py', 'w') as f:
    f.write(content)

print('  Applied vulnerability patch')
"

echo "Stage 3 complete."
