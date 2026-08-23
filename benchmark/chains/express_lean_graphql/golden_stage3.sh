#!/bin/bash
# Stage 3: Fix normalization with .lean() (BUG-550)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding .lean() to fix normalization (BUG-550)..."

USER_SVC="src/services/user.service.js"

sed -i.bak 's/return User\.findById(id);/return User.findById(id).lean();/' "$USER_SVC"
rm -f "$USER_SVC.bak"

echo "  Added .lean() to getUserById query"
echo "Stage 3 complete."
