#!/bin/bash
# Stage 1: Add editor role for content management (DX-310)
# Adds an intermediate 'editor' role with getUsers + manageUsers rights.
# Pure RBAC improvement — no security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding editor role (DX-310)..."

# 1. Update src/config/roles.js — add editor role
python3 -c "
with open('src/config/roles.js', 'r') as f:
    content = f.read()

original = content

# Add editor role between user and admin
content = content.replace(
    \"const allRoles = {\n  user: [],\n  admin: ['getUsers', 'manageUsers'],\n};\",
    \"const allRoles = {\n  user: [],\n  editor: ['getUsers', 'manageUsers'],\n  admin: ['getUsers', 'manageUsers'],\n};\"
)

if content == original:
    import sys
    print('ERROR: Could not patch allRoles in roles.js', file=sys.stderr)
    sys.exit(1)

with open('src/config/roles.js', 'w') as f:
    f.write(content)

print('  Added editor role to allRoles config')
"

# 2. Update src/validations/user.validation.js — allow editor in createUser
python3 -c "
with open('src/validations/user.validation.js', 'r') as f:
    content = f.read()

original = content

content = content.replace(
    \"role: Joi.string().required().valid('user', 'admin'),\",
    \"role: Joi.string().required().valid('user', 'editor', 'admin'),\"
)

if content == original:
    import sys
    print('ERROR: Could not patch role validation', file=sys.stderr)
    sys.exit(1)

with open('src/validations/user.validation.js', 'w') as f:
    f.write(content)

print('  Updated user validation to accept editor role')
"

echo "Stage 1 complete."
