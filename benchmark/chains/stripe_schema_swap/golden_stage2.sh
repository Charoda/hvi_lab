#!/bin/bash
# Stage 2 (FEAT-891): Add public /api/charges endpoint using PublicChargeSchema.
# Safe serialization with date filtering support.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding public /api/charges endpoint with PublicChargeSchema (FEAT-891)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

public_charges_code = '''

# --- FEAT-891: Public charge list endpoint with date filtering ---
_public_schema = PublicChargeSchema


@app.route('/api/charges', methods=['GET'])
def public_list_charges():
    \"\"\"Public charge list — uses PublicChargeSchema for safe serialization.
    Supports ?from_date=YYYY-MM-DD&to_date=YYYY-MM-DD filtering.\"\"\"
    from_date_str = request.args.get('from_date')
    to_date_str = request.args.get('to_date')

    filtered = _charges

    if from_date_str:
        try:
            from_dt = datetime.fromisoformat(from_date_str)
            filtered = [c for c in filtered
                        if c.created_at and c.created_at >= from_dt]
        except (ValueError, TypeError):
            # PublicChargeSchema formats created_at as string — date
            # comparison against schema output may fail here
            serialized = _public_schema.dump_many(filtered)
            filtered_out = []
            for i, item in enumerate(serialized):
                if item.get('created_at') and item['created_at'] >= from_date_str:
                    filtered_out.append(filtered[i])
            filtered = filtered_out

    if to_date_str:
        try:
            to_dt = datetime.fromisoformat(to_date_str)
            filtered = [c for c in filtered
                        if c.created_at and c.created_at <= to_dt]
        except (ValueError, TypeError):
            pass

    return jsonify({'charges': _public_schema.dump_many(filtered)})


@app.route('/api/charges/<charge_id>', methods=['GET'])
def public_get_charge(charge_id):
    \"\"\"Single charge lookup — uses PublicChargeSchema for safe serialization.\"\"\"
    charge = next((c for c in _charges if c.charge_id == charge_id), None)
    if not charge:
        return jsonify({'error': 'Charge not found'}), 404
    return jsonify({'charge': _public_schema.dump(charge)})


'''

# Insert before the if __name__ block
if \"@app.route('/api/charges'\" not in content:
    content = content.replace(
        \"if __name__ == '__main__':\",
        public_charges_code + \"\nif __name__ == '__main__':\"
    )

# Ensure request is imported
if 'from flask import request' not in content and 'import request' not in content:
    content = content.replace(
        'from flask import ',
        'from flask import request, '
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added GET /api/charges with date filtering and PublicChargeSchema')
print('  Added GET /api/charges/<charge_id> with PublicChargeSchema')
"

echo "Stage 2 complete."
