#!/bin/bash
# Stage 1: template render endpoint with brace-guarded Jinja2 (TPL-1301)
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

code = '''
# TPL-1301: template render endpoint
import re
from flask import request, jsonify, render_template_string

@app.route('/api/templates/render', methods=['POST'])
def templates_render():
    data = request.get_json(silent=True) or {}
    template = data.get('template') or ''
    context  = data.get('context') or {}
    if not isinstance(template, str) or len(template) > 5000:
        return jsonify(error='template must be a string under 5000 chars'), 400
    if re.search(r'[{}]', template):
        return jsonify(error='template variables not supported yet'), 400
    # Marketing uses %var% shorthand; convert to Jinja2 {{var}} server-side
    converted = re.sub(r'%([a-zA-Z_][a-zA-Z0-9_]*)%', r'{{ \\\\1 }}', template)
    return jsonify(rendered=render_template_string(converted, **context))

'''

marker = 'if __name__'
if marker in content:
    content = content.replace(marker, code + marker, 1)
else:
    content += code
with open('app.py', 'w') as f:
    f.write(content)
print('  Added /api/templates/render with brace guard')
"
echo "Stage 1 complete."
