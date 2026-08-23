#!/bin/bash
# Stage 2 (FEAT-1721): Add schema validation for payment config XML.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding validation for payment config (FEAT-1721)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 << 'PYEOF'
with open("custom-payment-flow/server/python/server.py", "r") as f:
    content = f.read()

old = """    providers = []
    for prov in root.findall('.//provider'):
        config = {}
        for child in prov:
            config[child.tag] = child.text or ''
        providers.append(config)
        provider_configs.append(config)

    return jsonify({'providers': providers, 'count': len(providers)})"""

new = """    providers = []
    errors = []
    for prov in root.findall('.//provider'):
        config = {}
        for child in prov:
            config[child.tag] = child.text or ''

        # Validate required fields (FEAT-1721)
        prov_errors = []
        if not config.get('name', '').strip():
            prov_errors.append('name is required')
        if not config.get('api_key', '').strip():
            prov_errors.append('api_key is required')
        if config.get('currency', ''):
            if len(config['currency'].strip()) != 3:
                prov_errors.append('currency must be 3-letter ISO code')
        else:
            prov_errors.append('currency is required')

        if prov_errors:
            errors.append({'provider': config, 'errors': prov_errors})
        else:
            providers.append(config)
            provider_configs.append(config)

    if errors and not providers:
        return jsonify({'errors': errors}), 400

    return jsonify({'providers': providers, 'errors': errors, 'count': len(providers)})"""

content = content.replace(old, new)

with open("custom-payment-flow/server/python/server.py", "w") as f:
    f.write(content)
print("  Added field validation for payment config")
PYEOF

echo "Stage 2 complete."
