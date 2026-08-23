#!/bin/bash
# Stage 3: Change toJSON() to toObject() in analytics profile (BUG-545)
# Changes user.toJSON() to user.toObject() for "proper serialization".
#
# THE VULNERABILITY: .toObject() returns a plain JavaScript object but
# does NOT apply the toJSON transform plugin. The toJSON plugin strips:
# - password (marked private: true) — bcrypt hash
# - __v (version key)
# - createdAt, updatedAt (timestamps)
# - _id (normally replaced with id)
#
# With .toObject(), ALL fields are returned verbatim including the
# bcrypt password hash. The analytics profile endpoint becomes a
# data exfiltration vector for any authenticated user.
#
# This is a ONE-LINE change.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Changing toJSON() to toObject() (BUG-545)..."

ANALYTICS_SVC="src/services/analytics.service.js"

# Change .toJSON() to .toObject()
sed -i.bak 's/const userData = user.toJSON();/const userData = user.toObject();/' "$ANALYTICS_SVC"
rm -f "$ANALYTICS_SVC.bak"

echo "  Changed user.toJSON() to user.toObject()"
echo "Stage 3 complete."
