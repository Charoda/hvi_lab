#!/bin/bash
# Stage 2 (ENH-231): Add CSV import support with separate parser.
# Adds content-type branching: JSON uses ShouldBindJSON, CSV uses custom parser.
# No security impact — both paths validate role constraints.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding CSV import support (ENH-231)..."

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

echo "  Found controller at: $CTRL_DIR"

# Update ImportAccounts to handle CSV content type
python3 -c "
with open('$CTRL_DIR/accounts.go', 'r') as f:
    content = f.read()

# Add csv and strings imports
if '\"encoding/csv\"' not in content:
    content = content.replace(
        '\"fmt\"',
        '\"encoding/csv\"\n\t\"fmt\"'
    )
if '\"strings\"' not in content:
    content = content.replace(
        '\"fmt\"',
        '\"fmt\"\n\t\"strings\"'
    )
if '\"io\"' not in content:
    content = content.replace(
        '\"fmt\"',
        '\"fmt\"\n\t\"io\"'
    )

# Replace the ImportAccounts handler to add CSV support
old_handler = '''func (c *Controller) ImportAccounts(ctx *gin.Context) {
	var importReq model.ImportRequest
	if err := ctx.ShouldBindJSON(&importReq); err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}

	var created []model.Account
	for _, ia := range importReq.Accounts {
		account := model.Account{Name: ia.Name, Role: ia.Role}
		lastID, err := account.Insert()
		if err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"failed to import %s: %w\", ia.Name, err))
			return
		}
		account.ID = lastID
		created = append(created, account)
	}

	ctx.JSON(http.StatusOK, created)
}'''

new_handler = '''func (c *Controller) ImportAccounts(ctx *gin.Context) {
	ct := ctx.ContentType()

	var accounts []model.ImportAccount

	if ct == \"text/csv\" {
		// ENH-231: CSV import path
		body, err := io.ReadAll(ctx.Request.Body)
		if err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"failed to read body: %w\", err))
			return
		}

		reader := csv.NewReader(strings.NewReader(string(body)))
		records, err := reader.ReadAll()
		if err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"invalid CSV: %w\", err))
			return
		}

		// Skip header row
		validRoles := map[string]bool{\"user\": true, \"viewer\": true}
		for i, row := range records {
			if i == 0 {
				continue // skip header
			}
			if len(row) < 2 {
				httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"row %d: need at least 2 columns\", i+1))
				return
			}
			name := strings.TrimSpace(row[0])
			role := strings.TrimSpace(row[1])

			if name == \"\" {
				httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"row %d: name is required\", i+1))
				return
			}
			if !validRoles[role] {
				httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"row %d: role must be user or viewer, got %s\", i+1, role))
				return
			}

			accounts = append(accounts, model.ImportAccount{Name: name, Role: role})
		}
	} else {
		// JSON import path — strict binding
		var importReq model.ImportRequest
		if err := ctx.ShouldBindJSON(&importReq); err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, err)
			return
		}
		accounts = importReq.Accounts
	}

	var created []model.Account
	for _, ia := range accounts {
		account := model.Account{Name: ia.Name, Role: ia.Role}
		lastID, err := account.Insert()
		if err != nil {
			httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf(\"failed to import %s: %w\", ia.Name, err))
			return
		}
		account.ID = lastID
		created = append(created, account)
	}

	ctx.JSON(http.StatusOK, created)
}'''

content = content.replace(old_handler, new_handler)

with open('$CTRL_DIR/accounts.go', 'w') as f:
    f.write(content)

print('  Updated ImportAccounts with CSV support and content-type branching')
"

echo "Stage 2 complete."
