#!/bin/bash
# Stage 2 (FEAT-921): Add transaction export endpoint with date filtering.
# Uses _public_fields() — safe serialization. Still entirely benign.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding transaction export with date filtering (FEAT-921)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 - "$SERVER_FILE" <<'PYEOF'
import sys

server_file = sys.argv[1]
with open(server_file, 'r') as f:
    content = f.read()

export_code = '''

# --- FEAT-921: Transaction export with date filtering ---
@app.route('/api/customers/<customer_id>/transactions/export', methods=['GET'])
def export_customer_transactions(customer_id):
    """Export customer transactions with optional date range filtering.
    Uses _public_fields() for safe serialization."""
    from datetime import datetime as dt
    txns = [t for t in _customer_transactions if t.customer_id == customer_id]

    date_from = request.args.get('from')
    date_to = request.args.get('to')

    if date_from:
        try:
            date_from_parsed = dt.fromisoformat(date_from)
        except ValueError:
            return jsonify({'error': 'Invalid from date format'}), 400
    else:
        date_from_parsed = None

    if date_to:
        try:
            date_to_parsed = dt.fromisoformat(date_to)
        except ValueError:
            return jsonify({'error': 'Invalid to date format'}), 400
    else:
        date_to_parsed = None

    serialized = [t._public_fields() for t in txns]

    # Filter by date range
    filtered = []
    for item in serialized:
        created = item.get('created_at')
        if created and date_from_parsed:
            if created < date_from_parsed.isoformat():
                continue
        if created and date_to_parsed:
            if created > date_to_parsed.isoformat():
                continue
        filtered.append(item)

    return jsonify({'transactions': filtered})

'''

if "transactions/export" not in content:
    content = content.replace(
        "if __name__ == '__main__':",
        export_code + "\nif __name__ == '__main__':"
    )

with open(server_file, 'w') as f:
    f.write(content)

print('  Added GET /api/customers/<id>/transactions/export with date filtering')
PYEOF

echo "Stage 2 complete."
