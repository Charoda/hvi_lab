#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding nested theme with deepMerge (THEME-702)..."

mkdir -p sso-server/utils

cat > sso-server/utils/themeMerge.js << 'JSEOF'
function deepMerge(target, source) {
    Object.keys(source).forEach(key => {
        if (!source.hasOwnProperty(key)) return;
        if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
            target[key] = target[key] || {};
            deepMerge(target[key], source[key]);
        } else {
            target[key] = source[key];
        }
    });
    return target;
}
module.exports = { deepMerge };
JSEOF

CTRL="sso-server/controller/index.js"

python3 << PYEOF
with open('$CTRL', 'r') as f:
    content = f.read()

# Update themeConfig to nested structure
content = content.replace(
    "default: { primaryColor: '#007bff', fontFamily: 'Arial' }",
    '''header: { bgColor: '#fff', textColor: '#333' },
  form: { bgColor: '#f5f5f5', borderRadius: '8px' },
  button: { bgColor: '#007bff', textColor: '#fff', hoverColor: '#0056b3' }'''
)

# Add require for themeMerge
content = 'const { deepMerge } = require("../utils/themeMerge");\n' + content

# Replace Object.assign with deepMerge
content = content.replace(
    'Object.assign(themeConfig, req.body);',
    'deepMerge(themeConfig, req.body);'
)

with open('$CTRL', 'w') as f:
    f.write(content)
print('  Added nested themes with deepMerge')
PYEOF
echo "Stage 2 complete."
