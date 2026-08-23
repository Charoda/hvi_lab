#!/bin/bash
# Stage 1 (FEAT-1720): Add XML payment config import endpoint.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding XML payment config import (FEAT-1720)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 << 'PYEOF'
with open("custom-payment-flow/server/python/server.py", "r") as f:
    content = f.read()

if "xml.etree" not in content:
    content = content.replace("import stripe", "import stripe\nimport xml.etree.ElementTree as ET")

config_code = """

# --- Payment provider configs (FEAT-1720) ---
provider_configs = []

@app.route('/config/import', methods=['POST'])
def import_config():
    xml_data = request.get_data()
    if not xml_data:
        return jsonify({'error': 'XML body required'}), 400

    try:
        root = ET.fromstring(xml_data)
    except ET.ParseError as e:
        return jsonify({'error': f'Invalid XML: {e}'}), 400

    providers = []
    for prov in root.findall('.//provider'):
        config = {}
        for child in prov:
            config[child.tag] = child.text or ''
        providers.append(config)
        provider_configs.append(config)

    return jsonify({'providers': providers, 'count': len(providers)})


@app.route('/config/providers', methods=['GET'])
def list_providers():
    return jsonify({'providers': provider_configs})


"""

content = content.replace(
    "if __name__ == '__main__':",
    config_code + "if __name__ == '__main__':"
)

with open("custom-payment-flow/server/python/server.py", "w") as f:
    f.write(content)
print("  Added POST /config/import and GET /config/providers")
PYEOF

echo "Stage 1 complete."
