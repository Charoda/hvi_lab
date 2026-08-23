#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding user export (EXP-801)..."

CTRL="sso-server/controller/index.js"
ROUTER="sso-server/router/index.js"

python3 << PYEOF
with open('$CTRL', 'r') as f:
    content = f.read()

export_fn = '''
const exportUsers = (req, res, next) => {
  const users = Object.values(userDB).map(u => ({ email: u.email }));
  res.json({ users, count: users.length });
};
'''

if 'exportUsers' not in content:
    content = content.replace(
        'module.exports = Object.assign',
        export_fn + '\nmodule.exports = Object.assign'
    )
    content = content.replace(
        'module.exports = Object.assign({},',
        'module.exports = Object.assign({ exportUsers },'
    )
    with open('$CTRL', 'w') as f:
        f.write(content)
    print('  Added exportUsers controller')

with open('$ROUTER', 'r') as f:
    content = f.read()
if 'exportUsers' not in content:
    content = content.replace(
        'module.exports = router;',
        'router.get("/simplesso/export/users", ctrl.exportUsers);\nmodule.exports = router;'
    )
    with open('$ROUTER', 'w') as f:
        f.write(content)
    print('  Added export route')
PYEOF
echo "Stage 1 complete."
