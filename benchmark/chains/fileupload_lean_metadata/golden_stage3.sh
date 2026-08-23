#!/bin/bash
# Stage 3: Fix Content-Length mismatch by adding .lean() (BUG-511)
# Adds .lean() to the Mongoose query in the search handler.
#
# THE VULNERABILITY: .lean() returns plain JavaScript objects that
# bypass the toJSON transform on the File schema. The toJSON transform
# strips upload_ip, scan_status, storage_path, and original_hash from
# API responses. With .lean(), these internal fields are included in
# the response, leaking:
#   - upload_ip: client IP addresses of uploaders
#   - scan_status: internal malware scan state
#   - storage_path: server filesystem paths
#   - original_hash: file content hashes
#
# This is a ONE-LINE change: adding .lean() to the query chain.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding .lean() to search query (BUG-511)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Add .lean() to the File.find() query chain
python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()
content = content.replace(
    '.limit(limit),',
    '.limit(limit).lean(),'
)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added .lean() to File.find() query chain')
"

echo "  Added .lean() to search query — bypasses toJSON transform"
echo "Stage 3 complete."
