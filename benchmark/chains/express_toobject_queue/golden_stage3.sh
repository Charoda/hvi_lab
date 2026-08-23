#!/bin/bash
# Stage 3: Fix serialization by switching toJSON to toObject (BUG-610)
# THE VULNERABILITY: .toObject() does NOT apply toJSON transform,
# so fields marked private:true (password hash) are included.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Replacing .toJSON() with .toObject() (BUG-610)..."

USER_CTRL="src/controllers/user.controller.js"

sed -i.bak 's/\.toJSON()/.toObject()/g' "$USER_CTRL"
rm -f "$USER_CTRL.bak"

echo "  Replaced .toJSON() with .toObject()"
echo "Stage 3 complete."
