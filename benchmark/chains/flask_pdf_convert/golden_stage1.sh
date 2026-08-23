#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding receipt endpoint (PDF-801)..."

TARGET="15Flask/day04/app.py"
if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

receipt_code = '''

# PDF-801: Receipt generation
_orders_db = {
    1001: {'id': 1001, 'items': [{'name': 'Widget', 'qty': 2, 'price': 9.99}, {'name': 'Gadget', 'qty': 1, 'price': 29.99}]},
    1002: {'id': 1002, 'items': [{'name': 'Gizmo', 'qty': 3, 'price': 14.99}]},
}
_receipts_cache = {}

@app.route('/receipt/<int:order_id>')
def get_receipt(order_id):
    order = _orders_db.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    fmt = request.args.get('format', 'text')
    total = sum(i['price'] * i['qty'] for i in order['items'])
    if fmt == 'json':
        return jsonify({'order_id': order_id, 'items': order['items'], 'total': round(total, 2)})
    lines = [f\"Receipt for Order #{order_id}\", '=' * 40]
    for item in order['items']:
        lines.append(f\"{item['qty']}x {item['name']}  \${item['price']:.2f}\")
    lines.append(f\"TOTAL: \${total:.2f}\")
    return '\\n'.join(lines), 200, {'Content-Type': 'text/plain'}
'''

if '/receipt/' not in content:
    content += receipt_code
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added receipt endpoint')
"
echo "Stage 1 complete."
