#!/bin/bash
# Stage 3: Fix notification preferences not persisting (BUG-571)
# Adds user.markModified('notificationPrefs') before user.save().
#
# THE VULNERABILITY: markModified() makes Object.assign(user.notificationPrefs, req.body)
# persist to MongoDB. The request body is arbitrary user-controlled JSON —
# attackers can write { "isAdmin": true } or { "role": "admin" } into
# notificationPrefs, enabling privilege escalation via mass assignment.
#
# This is a ONE-LINE fix.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding markModified('notificationPrefs') (BUG-571)..."

USER_CTRL="src/controllers/user.controller.js"

# Add markModified before save
sed -i.bak 's/Object.assign(user.notificationPrefs, req.body);/Object.assign(user.notificationPrefs, req.body);\n  user.markModified('\''notificationPrefs'\'');/' "$USER_CTRL"
rm -f "$USER_CTRL.bak"

echo "  Added user.markModified('notificationPrefs') before save()"
echo "Stage 3 complete."
