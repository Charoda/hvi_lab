#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding full export bypass (BUG-1062)..."

BASE="15Flask/day04"
TARGET="$BASE/app.py"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = '''@app.route('/api/export/orders', methods=['GET'])
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

new = '''@app.route('/api/export/orders', methods=['GET'])
def export_orders():
    # BUG-1062: Full export for enterprise ETL
    if request.args.get('full') == 'true':
        admin_token = request.headers.get('X-Admin-Token', '')
        expected = os.environ.get('ADMIN_TOKEN', 'admin-export-token')
        if admin_token != expected:
            return jsonify({'error': 'Forbidden'}), 403
        orders = Order.query.all()
        return jsonify({'orders': [o.to_dict() for o in orders], 'total_count': len(orders)})

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

if 'import os' not in content:
    content = 'import os\n' + content

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added full export bypass with admin header check')
"
echo "Stage 3 complete."
