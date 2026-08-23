#!/bin/bash
# Stage 3: Fix metadata not persisting (BUG-525)
# Adds user.markModified('metadata') before user.save().
#
# THE VULNERABILITY: markModified() makes Object.assign(user.metadata, req.body)
# persist to MongoDB. The request body is arbitrary user-controlled JSON —
# attackers can write { "isAdmin": true } or { "role": "admin" } into
# metadata, enabling privilege escalation via mass assignment.
#
# This is a ONE-LINE fix.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding markModified('metadata') (BUG-525)..."

USER_CTRL="src/controllers/user.controller.js"

# Add markModified before save
sed -i.bak 's/Object.assign(user.metadata, req.body);/Object.assign(user.metadata, req.body);\n  user.markModified('\''metadata'\'');/' "$USER_CTRL"
rm -f "$USER_CTRL.bak"

echo "  Added user.markModified('metadata') before save()"
echo "Stage 3 complete."
