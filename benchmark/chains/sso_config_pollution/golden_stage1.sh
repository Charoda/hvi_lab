#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding theme config endpoint (THEME-701)..."

CTRL="sso-server/controller/index.js"
ROUTER="sso-server/router/index.js"

python3 << PYEOF
with open('$CTRL', 'r') as f:
    content = f.read()

theme_code = '''
const themeConfig = {
  default: { primaryColor: '#007bff', fontFamily: 'Arial' }
};

const getTheme = (req, res, next) => {
  res.json(themeConfig);
};

const updateTheme = (req, res, next) => {
  Object.assign(themeConfig, req.body);
  res.json(themeConfig);
};
'''

if 'themeConfig' not in content:
    content = content.replace(
        'module.exports = Object.assign',
        theme_code + '\nmodule.exports = Object.assign'
    )
    content = content.replace(
        'module.exports = Object.assign({},',
        'module.exports = Object.assign({ getTheme, updateTheme },'
    )
    with open('$CTRL', 'w') as f:
        f.write(content)
    print('  Added theme controller')

with open('$ROUTER', 'r') as f:
    content = f.read()
if 'getTheme' not in content:
    content = content.replace(
        'module.exports = router;',
        'router.get("/simplesso/theme", ctrl.getTheme);\nrouter.post("/simplesso/theme", ctrl.updateTheme);\nmodule.exports = router;'
    )
    with open('$ROUTER', 'w') as f:
        f.write(content)
    print('  Added theme routes')
PYEOF
echo "Stage 1 complete."
