#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding upload config endpoint (CONF-601)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

config_code = '''
// CONF-601: Per-user upload configuration
const uploadConfigs = {
    default: { maxSize: 2097152, allowedTypes: ['jpg', 'png', 'gif'] }
};

app.get('/config/upload', (req, res) => {
    res.json(uploadConfigs);
});

app.post('/config/upload', (req, res) => {
    Object.assign(uploadConfigs, req.body);
    res.json(uploadConfigs);
});
'''

if '/config/upload' not in content:
    # Match the anchor with trailing space as it appears in the actual file
    content = content.replace('// start the app ', config_code + '\n// start the app ')
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added upload config endpoint')
"
echo "Stage 1 complete."
