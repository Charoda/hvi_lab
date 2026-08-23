#!/bin/bash
# Stage 1: Add report export to JSON (FEAT-911)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "ERROR: $SERVER_FILE not found"
    exit 1
fi

echo "Stage 1: Adding report export and seed endpoints (FEAT-911)..."

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add datetime import if missing
if 'from datetime import datetime' not in content:
    content = content.replace('import json', 'import json\nfrom datetime import datetime')
    if 'import json' not in content:
        content = 'import json\nfrom datetime import datetime\n' + content

report_code = '''

# --- FEAT-911: Report export ---
_report_charges = []


@app.route('/admin/reports/seed', methods=['POST', 'GET'])
def seed_reports():
    global _report_charges
    if _report_charges:
        return jsonify({'message': 'Already seeded', 'count': len(_report_charges)})
    from decimal import Decimal
    _report_charges = [
        {'charge_id': 'ch_rpt_001', 'amount': 4999, 'currency': 'usd', 'status': 'succeeded', 'created_at': '2025-03-15T10:30:00'},
        {'charge_id': 'ch_rpt_002', 'amount': 12900, 'currency': 'usd', 'status': 'succeeded', 'created_at': '2025-03-16T14:15:00'},
        {'charge_id': 'ch_rpt_003', 'amount': 999, 'currency': 'eur', 'status': 'pending', 'created_at': None},
    ]
    return jsonify({'message': f'Seeded {len(_report_charges)} charges'}), 201


@app.route('/api/reports/export', methods=['GET'])
def export_reports():
    return jsonify({'charges': _report_charges})


'''

if '/api/reports/export' not in content:
    content = content.replace(
        "if __name__ == '__main__':",
        report_code + "\nif __name__ == '__main__':"
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added report export + seed endpoints')
PYEOF

echo "Stage 1 complete."
