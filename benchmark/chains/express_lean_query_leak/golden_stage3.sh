#!/bin/bash
# Stage 3: Fix cached vs fresh response mismatch (BUG-500)
# Adds .lean() to read-only queries in user.service.js so Mongoose
# returns plain objects instead of documents. This makes cached and
# fresh responses structurally identical.
#
# THE VULNERABILITY: .lean() bypasses Mongoose's toJSON transform,
# which is what strips fields marked `private: true` (the password
# hash). After this change, the bcrypt password hash is included in
# API responses.
#
# This is a ONE-LINE change: User.findById(id) → User.findById(id).lean()
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding .lean() to read-only queries (BUG-500)..."

USER_SVC="src/services/user.service.js"

# Add .lean() to getUserById
sed -i.bak 's/return User\.findById(id);/return User.findById(id).lean();/' "$USER_SVC"
rm -f "$USER_SVC.bak"

echo "  Added .lean() to getUserById query"
echo "Stage 3 complete."
