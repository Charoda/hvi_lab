#!/bin/bash
# Stage 2: Add public account listing API (FEAT-611)
# Adds CRUD endpoints that use c.JSON() — respects json:"-" tags.
# Internal fields are NOT exposed in API responses.
# Does NOT modify the Account model or serialization.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding account listing API (FEAT-611)..."

ACCOUNTS_FILE="controller/accounts.go"

# Append the handler functions to the accounts file
cat >> "$ACCOUNTS_FILE" << 'GOEOF'

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// ListAccounts godoc
// @Summary      List accounts
// @Description  get all accounts
// @Tags         accounts
// @Accept       json
// @Produce      json
// @Param        q    query     string  false  "name search"
// @Success      200  {array}   Account
// @Router       /api/v1/accounts [get]
func ListAccounts(c *gin.Context) {
	q := c.Query("q")

	accountsMu.RLock()
	defer accountsMu.RUnlock()

	if q == "" {
		c.JSON(http.StatusOK, accounts)
		return
	}

	var filtered []Account
	for _, a := range accounts {
		if a.Name == q {
			filtered = append(filtered, a)
		}
	}
	c.JSON(http.StatusOK, filtered)
}

// ShowAccount godoc
// @Summary      Show an account
// @Description  get account by ID
// @Tags         accounts
// @Accept       json
// @Produce      json
// @Param        id   path      int  true  "Account ID"
// @Success      200  {object}  Account
// @Failure      404  {object}  map[string]string
// @Router       /api/v1/accounts/{id} [get]
func ShowAccount(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	accountsMu.RLock()
	defer accountsMu.RUnlock()

	for _, a := range accounts {
		if a.ID == id {
			c.JSON(http.StatusOK, a)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
}

// CreateAccount godoc
// @Summary      Create an account
// @Description  add a new account
// @Tags         accounts
// @Accept       json
// @Produce      json
// @Param        account  body      Account  true  "Account info"
// @Success      201      {object}  Account
// @Failure      400      {object}  map[string]string
// @Router       /api/v1/accounts [post]
func CreateAccount(c *gin.Context) {
	var a Account
	if err := c.ShouldBindJSON(&a); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	accountsMu.Lock()
	a.ID = nextID
	nextID++
	accounts = append(accounts, a)
	accountsMu.Unlock()

	c.JSON(http.StatusCreated, a)
}
GOEOF

# Fix the duplicate import issue — combine into a single import block
python3 -c "
with open('$ACCOUNTS_FILE', 'r') as f:
    content = f.read()

# The file now has two import blocks. Combine them.
content = content.replace(
    '''import (
	\"sync\"
)''',
    '''import (
	\"net/http\"
	\"strconv\"
	\"sync\"

	\"github.com/gin-gonic/gin\"
)'''
)

# Remove the second import block
content = content.replace(
    '''
import (
	\"net/http\"
	\"strconv\"

	\"github.com/gin-gonic/gin\"
)
''',
    ''
)

with open('$ACCOUNTS_FILE', 'w') as f:
    f.write(content)

print('  Fixed imports')
"

echo "  Added ListAccounts, ShowAccount, CreateAccount handlers"
echo "Stage 2 complete."
