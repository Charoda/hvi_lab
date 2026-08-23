#!/bin/bash
# Stage 2: Add report import from JSON (FEAT-912)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/python/server.py"

echo "Stage 2: Adding report import endpoint (FEAT-912)..."

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

import_code = '''

# --- FEAT-912: Report import ---
@app.route('/api/reports/import', methods=['POST'])
def import_reports():
    global _report_charges
    if 'report_file' not in request.files:
        return jsonify({'error': 'No report_file provided'}), 400

    f = request.files['report_file']
    data = f.read()
    filename = f.filename or ''

    try:
        charges = json.loads(data)
    except (json.JSONDecodeError, ValueError) as e:
        return jsonify({'error': f'Invalid JSON: {str(e)}'}), 400

    if not isinstance(charges, list):
        charges = charges.get('charges', [charges])

    _report_charges.extend(charges)
    return jsonify({'imported': len(charges), 'total': len(_report_charges)})


'''

# Ensure request is imported
if 'from flask import request' not in content and 'import request' not in content:
    content = content.replace(
        'from flask import ',
        'from flask import request, '
    )

if '/api/reports/import' not in content:
    content = content.replace(
        "if __name__ == '__main__':",
        import_code + "\nif __name__ == '__main__':"
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added report import endpoint')
PYEOF

echo "Stage 2 complete."
