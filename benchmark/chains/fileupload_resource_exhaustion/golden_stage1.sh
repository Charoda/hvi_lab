#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

TARGET="nodejs/express-multer/index.js"

echo "Stage 1: Adding file listing with pagination (FEAT-1100)..."

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add file registry if not present
if 'fileRegistry' not in content:
    # Add registry after the uploadLog/quotas declarations
    registry_code = '''
const fileRegistry = [];

const registerFile = (file, userId) => {
  fileRegistry.push({
    name: file.originalname,
    storedName: file.filename,
    size: file.size,
    mimetype: file.mimetype,
    uploadedBy: userId || 'anonymous',
    uploadedAt: new Date().toISOString(),
  });
};
'''
    # Insert after the quotas declaration
    if 'const quotas' in content:
        content = content.replace('const quotas = {};', 'const quotas = {};' + registry_code)
    else:
        # Insert after uploadLog
        content = content.replace('const uploadLog = {};', 'const uploadLog = {};' + registry_code)

# Register files on upload
if 'registerFile' not in content or 'registerFile(req.file' not in content:
    # Add registerFile call in upload-avatar
    content = content.replace(
        \"return res.send({\\n        status: true,\\n        message: 'File is uploaded.',\",
        \"registerFile(req.file, 'avatar');\\n    return res.send({\\n        status: true,\\n        message: 'File is uploaded.',\"
    )

# Add file listing endpoint
if \"app.get('/files'\" not in content:
    listing_endpoint = '''
app.get('/files', (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  const total = fileRegistry.length;
  const files = fileRegistry.slice(offset, offset + limit);

  return res.json({ files, page, limit, total });
});
'''
    # Insert before the port/listen block
    content = content.replace(
        \"const port = process.env.PORT\",
        listing_endpoint + \"\\nconst port = process.env.PORT\"
    )

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added file registry and GET /files endpoint')
"

echo "Stage 1 complete."
