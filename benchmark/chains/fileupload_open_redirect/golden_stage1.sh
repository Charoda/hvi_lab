#!/bin/bash
# Stage 1 (FEAT-460): Add callback redirect parameter on upload-avatar.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding callback redirect on upload-avatar..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

# Add callback redirect after successful upload
callback_code = '''
// Callback redirect support (FEAT-460)
function handleUploadResponse(req, res, filename) {
    const callback = req.query.callback;
    if (callback) {
        const sep = callback.includes('?') ? '&' : '?';
        return res.redirect(callback + sep + 'status=success&filename=' + filename);
    }
    return null;  // fall through to JSON response
}
'''

insert_point = content.find('app.')
if insert_point == -1:
    insert_point = content.find('router.')
if insert_point > 0:
    content = content[:insert_point] + callback_code + '\n' + content[insert_point:]

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added callback redirect handler')
PYEOF

echo "Stage 1 complete."
