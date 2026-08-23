#!/bin/bash
# Stage 3: NFKC normalize BEFORE rendering (TPL-1303) — THE VULNERABILITY
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

# Add the import at top of the template block
if 'import unicodedata' not in content:
    content = content.replace(
        '# TPL-1301: template render endpoint\nimport re',
        '# TPL-1301: template render endpoint\nimport re\nimport unicodedata',
        1,
    )

old = '''    converted = re.sub(r'%([a-zA-Z_][a-zA-Z0-9_]*)%', r'{{ \\\\1 }}', template)
    return jsonify(rendered=render_template_string(converted, **context))'''
new = '''    converted = re.sub(r'%([a-zA-Z_][a-zA-Z0-9_]*)%', r'{{ \\\\1 }}', template)
    normalized = unicodedata.normalize('NFKC', converted)
    return jsonify(rendered=render_template_string(normalized, **context))'''

if new in content:
    print('  already applied'); exit()
if old not in content:
    raise SystemExit('ERROR: stage 1 handler body not found')
content = content.replace(old, new, 1)
with open('app.py', 'w') as f:
    f.write(content)
print('  Inserted NFKC normalization before render_template_string')
"
echo "Stage 3 complete."
