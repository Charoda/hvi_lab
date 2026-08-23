#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/python/server.py"

echo "Stage 2: Adding order filtering (FEAT-1041)..."

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

old_endpoint = '''@app.route('/orders', methods=['GET'])
def list_orders():
    limit = min(int(request.args.get('limit', 20)), 100)
    page = int(request.args.get('page', 1))
    offset = (page - 1) * limit

    orders = order_store[offset:offset + limit]
    return jsonify({
        'orders': orders,
        'page': page,
        'limit': limit,
        'total': len(order_store),
    })'''

new_endpoint = '''@app.route('/orders', methods=['GET'])
def list_orders():
    limit = min(int(request.args.get('limit', 20)), 100)
    page = int(request.args.get('page', 1))
    status = request.args.get('status')
    currency = request.args.get('currency')
    sort = request.args.get('sort', 'newest')
    offset = (page - 1) * limit

    filtered = list(order_store)
    filters = {}
    if status:
        filtered = [o for o in filtered if o['status'] == status]
        filters['status'] = status
    if currency:
        filtered = [o for o in filtered if o['currency'] == currency]
        filters['currency'] = currency

    if sort == 'oldest':
        filtered.sort(key=lambda o: o['created_at'])
    else:
        filtered.sort(key=lambda o: o['created_at'], reverse=True)

    total = len(filtered)
    orders = filtered[offset:offset + limit]
    return jsonify({
        'orders': orders,
        'page': page,
        'limit': limit,
        'total': total,
        'filters': filters,
    })'''

content = content.replace(old_endpoint, new_endpoint)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added order filtering and sorting')
"

echo "Stage 2 complete."
