#!/bin/bash
# Stage 2: Add filters and conditional blocks to email templates (FEAT-971)
# Adds |upper, |lower, |currency, |truncate(N) filters and {{#if}} blocks
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 2: Adding template filters and conditionals (FEAT-971)..."

python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

# Replace the simple render function with one that supports filters and conditionals
old_render = '''@app.route('/api/templates/render', methods=['POST'])
def render_template_endpoint():
    from flask import request, jsonify
    data = request.get_json()
    template = data.get('template', '')
    context = data.get('context', {})

    # Validate variable names are alphanumeric only
    variables = _re.findall(r'\\\\{\\\\{\\\\s*(\\\\w+)\\\\s*\\\\}\\\\}', template)
    for var in variables:
        if not var.isalnum():
            return jsonify({'error': f'Invalid variable name: {var}'}), 400
        if var not in context:
            return jsonify({'error': f'Missing variable: {var}'}), 400

    # Safe regex-based substitution
    def replace_var(match):
        var_name = match.group(1).strip()
        return str(context.get(var_name, match.group(0)))

    rendered = _re.sub(r'\\\\{\\\\{\\\\s*(\\\\w+)\\\\s*\\\\}\\\\}', replace_var, template)
    return jsonify({'rendered': rendered, 'template': template})'''

new_render = '''# FEAT-971: Template filter functions
_TEMPLATE_FILTERS = {
    'upper': lambda v: str(v).upper(),
    'lower': lambda v: str(v).lower(),
    'currency': lambda v: f'\${float(v):.2f}',
}

def _apply_filter(value, filter_str):
    \"\"\"Apply a named filter to a value.\"\"\"
    truncate_match = _re.match(r'truncate\\((\\d+)\\)', filter_str)
    if truncate_match:
        n = int(truncate_match.group(1))
        s = str(value)
        return s[:n] + '...' if len(s) > n else s
    if filter_str in _TEMPLATE_FILTERS:
        return _TEMPLATE_FILTERS[filter_str](value)
    return None  # Unknown filter

def _process_conditionals(template, context):
    \"\"\"Process {{#if var}}...{{#else}}...{{/if}} blocks.\"\"\"
    pattern = r'\\{\\{#if\\s+(\\w+)\\}\\}(.*?)(?:\\{\\{#else\\}\\}(.*?))?\\{\\{/if\\}\\}'
    def replace_cond(match):
        var_name = match.group(1)
        true_block = match.group(2)
        false_block = match.group(3) or ''
        if context.get(var_name):
            return true_block
        return false_block
    return _re.sub(pattern, replace_cond, template, flags=_re.DOTALL)

@app.route('/api/templates/render', methods=['POST'])
def render_template_endpoint():
    from flask import request, jsonify
    data = request.get_json()
    template = data.get('template', '')
    context = data.get('context', {})

    # Process conditionals first
    template = _process_conditionals(template, context)

    # Handle variables with optional filters: {{var|filter1|filter2}}
    def replace_var(match):
        expr = match.group(1).strip()
        parts = expr.split('|')
        var_name = parts[0].strip()

        if not var_name.isalnum():
            return match.group(0)
        if var_name not in context:
            return match.group(0)

        value = context[var_name]
        # Apply filters in chain
        for f in parts[1:]:
            f = f.strip()
            result = _apply_filter(value, f)
            if result is None:
                return f'[unknown filter: {f}]'
            value = result
        return str(value)

    rendered = _re.sub(r'\\{\\{\\s*([^}]+?)\\s*\\}\\}', replace_var, template)
    return jsonify({'rendered': rendered, 'template': data.get('template', '')})'''

content = content.replace(old_render, new_render)

with open('app.py', 'w') as f:
    f.write(content)

print('  Added filter support and conditional blocks')
"

echo "Stage 2 complete."
