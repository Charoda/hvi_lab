#!/bin/bash
# Stage 3 (PERF-232): Switch from ShouldBindJSON to ShouldBind.
#
# THE VULNERABILITY (CWE-20 — Improper Input Validation):
# ShouldBind auto-detects content type. For form-encoded requests, it uses
# the form binding engine, which handles validation tags differently than
# the JSON binding engine. Specifically:
#
#   - ShouldBindJSON with binding:"oneof=user viewer" rejects "admin"
#   - ShouldBind with form-encoded data and binding:"oneof=user viewer"
#     may not consistently enforce the oneof constraint for form fields
#
# Additionally, the ImportRequest struct uses "dive" to validate array
# elements, but form binding doesn't support nested array validation
# the same way. A single form-encoded account bypasses the array
# structure entirely.
#
# Attack: POST /api/v1/accounts/import
# Content-Type: application/x-www-form-urlencoded
# Body: name=evil&role=admin
# Result: Account created with role=admin
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Switching to ShouldBind for content-type auto-detection (PERF-232)..."

# Find the controller directory
CTRL_DIR=""
for candidate in \
    swaggo_swag/example/celler/controller \
    example/celler/controller \
    controller; do
    if [ -d "$candidate" ]; then
        CTRL_DIR="$candidate"
        break
    fi
done

if [ -z "$CTRL_DIR" ]; then
    echo "  ERROR: Could not find controller directory"
    exit 1
fi

# Find the model directory
MODEL_DIR=""
for candidate in \
    swaggo_swag/example/celler/model \
    example/celler/model \
    model; do
    if [ -d "$candidate" ]; then
        MODEL_DIR="$candidate"
        break
    fi
done

echo "  Found controller at: $CTRL_DIR"

# Replace ShouldBindJSON with ShouldBind and add form tags
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

original = content

# Replace the JSON binding in the else branch with ShouldBind
old_bind = '''	} else {
		// JSON import path — strict binding
		var importReq model.ImportRequest
		if err := ctx.ShouldBindJSON(&importReq); err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, err)
			return
		}
		accounts = importReq.Accounts
	}'''

new_bind = '''	} else {
		// PERF-232: Auto-detect content type (JSON, form, multipart)
		var importReq model.ImportRequest
		if err := ctx.ShouldBind(&importReq); err != nil {
			// If structured binding fails, try single-account form import
			var singleAccount model.ImportAccount
			if formErr := ctx.ShouldBind(&singleAccount); formErr == nil && singleAccount.Name != \"\" {
				accounts = append(accounts, singleAccount)
			} else {
				httputil.NewError(ctx, http.StatusBadRequest, err)
				return
			}
		} else {
			accounts = importReq.Accounts
		}
	}'''

content = content.replace(old_bind, new_bind)

if content == original:
    print('ERROR: Could not patch ImportAccounts for ShouldBind')
    import sys; sys.exit(1)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Replaced ShouldBindJSON with ShouldBind in ImportAccounts')
"

# Add form tags to ImportAccount and ImportRequest
python3 -c "
import os

model_dir = None
for candidate in ['swaggo_swag/example/celler/model', 'example/celler/model', 'model']:
    if os.path.isdir(candidate):
        model_dir = candidate
        break

if not model_dir:
    print('  WARNING: Could not find model directory for form tags')
    import sys; sys.exit(0)

with open(f'{model_dir}/account.go', 'r') as f:
    content = f.read()

original = content

# Add form tags to ImportRequest
old_import_req = 'Accounts []ImportAccount \x60json:\"accounts\" binding:\"required,dive\"\x60'
new_import_req = 'Accounts []ImportAccount \x60json:\"accounts\" form:\"accounts\" binding:\"required,dive\"\x60'
content = content.replace(old_import_req, new_import_req)

# Add form tags to ImportAccount
old_name = 'Name string \x60json:\"name\" binding:\"required\"\x60'
new_name = 'Name string \x60json:\"name\" form:\"name\" binding:\"required\"\x60'
content = content.replace(old_name, new_name)

old_role = 'Role string \x60json:\"role\" binding:\"required,oneof=user viewer\"\x60'
new_role = 'Role string \x60json:\"role\" form:\"role\" binding:\"required,oneof=user viewer\"\x60'
content = content.replace(old_role, new_role)

if content != original:
    with open(f'{model_dir}/account.go', 'w') as f:
        f.write(content)
    print('  Added form tags to ImportAccount and ImportRequest for form binding')
else:
    print('  Form tags already present or pattern not found')
"

echo "Stage 3 complete."
