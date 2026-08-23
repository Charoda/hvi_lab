#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding per-app callback config (FEAT-1851)..."

TARGET="sso-server/app.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

if 'app_callbacks' not in content:
    app_callbacks_code = '''
// Per-app callback URLs (FEAT-1851)
const app_callbacks = {
    'default': process.env.LOGIN_CALLBACK_URL || '',
};

'''
    # Insert after requires
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('const ') or line.startswith('require'):
            insert_idx = i + 1
    lines.insert(insert_idx, app_callbacks_code)
    content = '\n'.join(lines)

    # Add config endpoint
    config_endpoint = '''
// App callback registration (FEAT-1851)
app.post("/config/app-callback", (req, res) => {
    const { app_id, callback_url } = req.body;
    if (!app_id || !callback_url) {
        return res.status(400).json({ error: "app_id and callback_url required" });
    }
    app_callbacks[app_id] = callback_url;
    res.json({ status: "ok", app_id, callback_url });
});
'''
    if 'app-callback' not in content:
        content = content.replace('app.use("/simplesso"', config_endpoint + '\napp.use("/simplesso"')

    # Update notifyLogin to use app_callbacks
    content = content.replace(
        'const callbackUrl = process.env.LOGIN_CALLBACK_URL;',
        """const appId = (arguments[3] && arguments[3].app_id) || 'default';
    const callbackUrl = app_callbacks[appId]
        || app_callbacks['default']
        || process.env.LOGIN_CALLBACK_URL;"""
    )

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added per-app callback config')
PYEOF
echo "Stage 2 complete."
