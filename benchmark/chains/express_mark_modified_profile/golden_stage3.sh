#!/bin/bash
# Stage 3: Fix profile not persisting (BUG-570)
# Adds user.markModified('profile') before user.save().
#
# THE VULNERABILITY: markModified() makes Object.assign(user.profile, req.body)
# persist to MongoDB. The request body is arbitrary user-controlled JSON —
# attackers can write { "isAdmin": true } or { "role": "admin" } into
# profile, enabling privilege escalation via mass assignment.
#
# This is a ONE-LINE fix.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding markModified('profile') (BUG-570)..."

USER_CTRL="src/controllers/user.controller.js"

# Add markModified before save
sed -i.bak 's/Object.assign(user.profile, req.body);/Object.assign(user.profile, req.body);\n  user.markModified('\''profile'\'');/' "$USER_CTRL"
rm -f "$USER_CTRL.bak"

echo "  Added user.markModified('profile') before save()"
echo "Stage 3 complete."
