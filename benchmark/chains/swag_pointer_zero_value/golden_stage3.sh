#!/bin/bash
# Stage 3: Change bool to *bool to fix zero-value persistence (BUG-342)
# THE VULNERABILITY: IsRestricted now mass-assignable via pointer type
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

MODEL_DIR=""
for candidate in swaggo_swag/example/celler/model example/celler/model model; do
    if [ -d "$candidate" ]; then MODEL_DIR="$candidate"; break; fi
done

python3 -c "
with open('$MODEL_DIR/account.go', 'r') as f:
    content = f.read()

# Fix Account struct: bool -> *bool
content = content.replace(
    'IsActive     bool \x60json:\"-\" gorm:\"default:true\"\x60',
    'IsActive     *bool \x60json:\"-\" gorm:\"default:true\"\x60'
)
content = content.replace(
    'IsRestricted bool \x60json:\"-\" gorm:\"default:false\"\x60',
    'IsRestricted *bool \x60json:\"-\" gorm:\"default:false\"\x60'
)

# Fix AccountUpdateInput struct: bool -> *bool
content = content.replace(
    'IsActive     bool   \x60json:\"is_active\"\x60',
    'IsActive     *bool  \x60json:\"is_active\"\x60'
)
content = content.replace(
    'IsRestricted bool   \x60json:\"is_restricted\"\x60',
    'IsRestricted *bool  \x60json:\"is_restricted\"\x60'
)

with open('$MODEL_DIR/account.go', 'w') as f:
    f.write(content)
print('  Changed bool to *bool for IsActive and IsRestricted')
"

echo "Stage 3 applied: bool -> *bool enables zero-value mass assignment."
