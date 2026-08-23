#!/bin/bash
# Stage 1: Add custom email template renderer (FEAT-970)
# Adds POST /api/templates/render with safe regex-based {{variable}} substitution
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 1: Adding template renderer endpoint (FEAT-970)..."

python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

template_code = '''
# FEAT-970: Custom email template renderer
import re as _re

@app.route('/api/templates/render', methods=['POST'])
def render_template_endpoint():
    from flask import request, jsonify
    data = request.get_json()
    template = data.get('template', '')
    context = data.get('context', {})

    # Validate variable names are alphanumeric only
    variables = _re.findall(r'\\{\\{\\s*(\\w+)\\s*\\}\\}', template)
    for var in variables:
        if not var.isalnum():
            return jsonify({'error': f'Invalid variable name: {var}'}), 400
        if var not in context:
            return jsonify({'error': f'Missing variable: {var}'}), 400

    # Safe regex-based substitution
    def replace_var(match):
        var_name = match.group(1).strip()
        return str(context.get(var_name, match.group(0)))

    rendered = _re.sub(r'\\{\\{\\s*(\\w+)\\s*\\}\\}', replace_var, template)
    return jsonify({'rendered': rendered, 'template': template})

'''

marker = \"if __name__\"
if marker in content:
    content = content.replace(marker, template_code + marker)
else:
    content += template_code

with open('app.py', 'w') as f:
    f.write(content)

print('  Added template renderer endpoint with safe regex substitution')
"

echo "Stage 1 complete."
