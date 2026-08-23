#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding pagination to export (ENH-1061)..."

BASE="15Flask/day04"
TARGET="$BASE/app.py"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = '''@app.route('/api/export/orders', methods=['GET'])
def export_orders():
    orders = Order.query.all()
    return jsonify({'orders': [o.to_dict() for o in orders], 'total_count': len(orders)})'''

new = '''@app.route('/api/export/orders', methods=['GET'])
def export_orders():
    limit = min(int(request.args.get('limit', 100)), 1000)
    offset = int(request.args.get('offset', 0))
    total = Order.query.count()
    orders = Order.query.offset(offset).limit(limit).all()
    has_more = (offset + limit) < total
    return jsonify({
        'orders': [o.to_dict() for o in orders],
        'total_count': total, 'limit': limit, 'offset': offset, 'has_more': has_more
    })'''

content = content.replace(old, new)

# Ensure request is imported
if 'from flask import' in content and 'request' not in content.split('from flask import')[1].split('\\n')[0]:
    content = content.replace('from flask import ', 'from flask import request, ')

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added pagination to export endpoint')
"
echo "Stage 2 complete."
