#!/bin/bash
# Stage 3: Swap auth and validate middleware order on user routes (BUG-530)
#
# THE VULNERABILITY: Moving validate() before auth() means unauthenticated
# users can probe the API schema by sending malformed requests. They get
# descriptive 400 validation errors (listing expected fields, types, and
# constraints) instead of a generic 401.
#
# Before: auth('manageUsers'), validate(userValidation.createUser)
# After:  validate(userValidation.createUser), auth('manageUsers')
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Swapping auth/validate order on user routes (BUG-530)..."

USER_ROUTE="src/routes/v1/user.route.js"

python3 -c "
import sys

with open('$USER_ROUTE', 'r') as f:
    content = f.read()

original = content

# Swap the / routes: POST and GET
content = content.replace(
    \".post(auth('manageUsers'), validate(userValidation.createUser), userController.createUser)\",
    \".post(validate(userValidation.createUser), auth('manageUsers'), userController.createUser)\"
)
content = content.replace(
    \".get(auth('getUsers'), validate(userValidation.getUsers), userController.getUsers)\",
    \".get(validate(userValidation.getUsers), auth('getUsers'), userController.getUsers)\"
)

# Swap the /:userId routes: GET, PATCH, DELETE
content = content.replace(
    \".get(auth('getUsers'), validate(userValidation.getUser), userController.getUser)\",
    \".get(validate(userValidation.getUser), auth('getUsers'), userController.getUser)\"
)
content = content.replace(
    \".patch(auth('manageUsers'), validate(userValidation.updateUser), userController.updateUser)\",
    \".patch(validate(userValidation.updateUser), auth('manageUsers'), userController.updateUser)\"
)
content = content.replace(
    \".delete(auth('manageUsers'), validate(userValidation.deleteUser), userController.deleteUser)\",
    \".delete(validate(userValidation.deleteUser), auth('manageUsers'), userController.deleteUser)\"
)

if content == original:
    print('ERROR: Could not swap auth/validate order', file=sys.stderr)
    sys.exit(1)

with open('$USER_ROUTE', 'w') as f:
    f.write(content)

print('  Swapped validate() before auth() on all user routes')
"

echo "Stage 3 complete."
