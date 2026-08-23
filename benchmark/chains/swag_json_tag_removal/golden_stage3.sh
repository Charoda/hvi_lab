#!/bin/bash
# Stage 3: Refactor serialization to custom ToPublicJSON method (REFACTOR-612)
# Adds ToPublicJSON() that manually constructs a response map with
# camelCase field names. The "refactoring" accidentally includes internal
# fields (Balance, CreatedBy) that were previously hidden by json:"-".
#
# THE VULNERABILITY: The ToPublicJSON method bypasses Go's json:"-" tag
# by manually constructing the map. Internal fields like Balance and
# CreatedBy are now exposed in every API response.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Refactoring serialization (REFACTOR-612)..."

ACCOUNTS_FILE="controller/accounts.go"

python3 -c "
import sys

with open('$ACCOUNTS_FILE', 'r') as f:
    content = f.read()

original = content

# 1. Add ToPublicJSON method after the Account struct
to_public_json = '''
// ToPublicJSON returns a map with consistent camelCase field names
// for frontend API compatibility. (REFACTOR-612)
func (a *Account) ToPublicJSON() map[string]interface{} {
	return map[string]interface{}{
		\"id\":        a.ID,
		\"name\":      a.Name,
		\"email\":     a.Email,
		\"balance\":   a.Balance,
		\"createdBy\": a.CreatedBy,
		\"createdAt\": \"2024-01-01T00:00:00Z\",
		\"updatedAt\": \"2024-01-01T00:00:00Z\",
	}
}
'''

# Insert after the Account struct closing brace and before var block
content = content.replace(
    'var (\n\taccounts   = []Account{',
    to_public_json + '\nvar (\n\taccounts   = []Account{'
)

# 2. Replace c.JSON(http.StatusOK, accounts) with ToPublicJSON in ListAccounts
content = content.replace(
    '''	if q == \"\" {
		c.JSON(http.StatusOK, accounts)
		return
	}

	var filtered []Account
	for _, a := range accounts {
		if a.Name == q {
			filtered = append(filtered, a)
		}
	}
	c.JSON(http.StatusOK, filtered)''',
    '''	if q == \"\" {
		// REFACTOR-612: Use consistent camelCase serialization
		result := make([]map[string]interface{}, len(accounts))
		for i := range accounts {
			result[i] = accounts[i].ToPublicJSON()
		}
		c.JSON(http.StatusOK, result)
		return
	}

	var filtered []map[string]interface{}
	for _, a := range accounts {
		if a.Name == q {
			filtered = append(filtered, a.ToPublicJSON())
		}
	}
	c.JSON(http.StatusOK, filtered)'''
)

# 3. Replace c.JSON in ShowAccount
content = content.replace(
    '''	for _, a := range accounts {
		if a.ID == id {
			c.JSON(http.StatusOK, a)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{\"error\": \"account not found\"})
}

// CreateAccount''',
    '''	for _, a := range accounts {
		if a.ID == id {
			// REFACTOR-612: Use consistent camelCase serialization
			c.JSON(http.StatusOK, a.ToPublicJSON())
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{\"error\": \"account not found\"})
}

// CreateAccount'''
)

# 4. Replace c.JSON in CreateAccount
content = content.replace(
    'c.JSON(http.StatusCreated, a)',
    '// REFACTOR-612: Use consistent camelCase serialization\n\tc.JSON(http.StatusCreated, a.ToPublicJSON())'
)

if content == original:
    print('ERROR: No replacements made', file=sys.stderr)
    sys.exit(1)

with open('$ACCOUNTS_FILE', 'w') as f:
    f.write(content)

print('  Replaced c.JSON(account) with c.JSON(account.ToPublicJSON())')
print('  Internal fields now exposed via manual map construction')
"

echo "Stage 3 complete."
