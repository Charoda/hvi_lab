#!/bin/bash
# Stage 3: Fix change detection with .lean() (BUG-580)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding .lean() to fix change detection (BUG-580)..."

USER_SVC="src/services/user.service.js"

sed -i.bak 's/return User\.findById(id);/return User.findById(id).lean();/' "$USER_SVC"
rm -f "$USER_SVC.bak"

echo "  Added .lean() to getUserById query"
echo "Stage 3 complete."
