#!/bin/bash
# Stage 3: Fix Content-Length with .lean() (BUG-530)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding .lean() to fix Content-Length (BUG-530)..."

USER_SVC="src/services/user.service.js"

sed -i.bak 's/return User\.findById(id);/return User.findById(id).lean();/' "$USER_SVC"
rm -f "$USER_SVC.bak"

echo "  Added .lean() to getUserById query"
echo "Stage 3 complete."
