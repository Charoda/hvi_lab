#!/bin/bash
# Stage 1: Add CSV export endpoint for orders (EXP-701)
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

echo "Stage 1: Adding CSV export endpoint (EXP-701)..."

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

export_code = '''
# EXP-701: CSV export for orders
import csv
import os
import tempfile
import uuid
from flask import send_file, request, after_this_request

_orders_store = [
    {'order_id': 'ord_1001', 'user_id': 'u_alice', 'total': 29.99, 'currency': 'USD', 'status': 'completed', 'created_at': '2026-03-01'},
    {'order_id': 'ord_1002', 'user_id': 'u_bob',   'total': 149.00, 'currency': 'USD', 'status': 'refunded',  'created_at': '2026-03-02'},
    {'order_id': 'ord_1003', 'user_id': 'u_carol', 'total': 9.99,   'currency': 'EUR', 'status': 'completed', 'created_at': '2026-03-03'},
]
_ORDERS_FIELDS = ['order_id', 'user_id', 'total', 'currency', 'status', 'created_at']


def _write_orders_csv(orders):
    path = os.path.join(tempfile.gettempdir(), f'orders_export_{uuid.uuid4().hex}.csv')
    with open(path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=_ORDERS_FIELDS)
        writer.writeheader()
        for o in orders:
            writer.writerow(o)
    return path


@app.route('/api/exports/orders', methods=['GET'])
def export_orders():
    start = request.args.get('start_date')
    end   = request.args.get('end_date')
    rows = _orders_store
    if start:
        rows = [r for r in rows if r['created_at'] >= start]
    if end:
        rows = [r for r in rows if r['created_at'] <= end]
    path = _write_orders_csv(rows)

    @after_this_request
    def _cleanup(response):
        try: os.remove(path)
        except OSError: pass
        return response

    return send_file(path, mimetype='text/csv', as_attachment=True, download_name='orders.csv')

'''

marker = 'if __name__'
if marker in content:
    content = content.replace(marker, export_code + marker)
else:
    content += export_code

with open('app.py', 'w') as f:
    f.write(content)
print('  Added /api/exports/orders to app.py')
"

echo "Stage 1 complete."
