#!/bin/bash
# Stage 1 (FEAT-620): Add return_url redirect after POST /accounts.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding return_url redirect on account creation..."

ACCOUNTS_FILE="example/celler/controller/accounts.go"
if [ ! -f "$ACCOUNTS_FILE" ]; then
    echo "  ERROR: $ACCOUNTS_FILE not found"
    exit 1
fi

python3 << 'PYEOF'
with open('example/celler/controller/accounts.go', 'r') as f:
    content = f.read()

# Add needed imports
old_imports = '''import (
	"github.com/gin-gonic/gin"
)'''

new_imports = '''import (
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"sync"

	"github.com/gin-gonic/gin"
)'''

if old_imports not in content:
    raise RuntimeError("Import block pattern not found in accounts.go")

content = content.replace(old_imports, new_imports)

# Add Account types and state before ShowAccount
types_and_state = '''
// Account represents a user account
type Account struct {
	ID    int    `json:"id" example:"1"`
	Name  string `json:"name" example:"account name"`
	Email string `json:"email" example:"account@example.com"`
}

// AddAccount represents account creation input
type AddAccount struct {
	Name string `json:"name" example:"account name"`
}

// Validation validates the AddAccount input
func (a AddAccount) Validation() error {
	if len(a.Name) == 0 {
		return fmt.Errorf("name is empty")
	}
	return nil
}

var (
	accounts   = []Account{
		{ID: 1, Name: "account_1"},
		{ID: 2, Name: "account_2"},
		{ID: 3, Name: "account_3"},
	}
	accountsMu   sync.RWMutex
	accountMaxID = 3
)

'''

content = content.replace(
    '// ShowAccount godoc',
    types_and_state + '// ShowAccount godoc',
    1  # only first occurrence
)

# Replace ShowAccount with real implementation
old_show = '''func (c *Controller) ShowAccount(ctx *gin.Context) {
	// TODO: implement ShowAccount handler.
	panic("TODO: implement ShowAccount")
}'''

new_show = '''func (c *Controller) ShowAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	accountsMu.RLock()
	defer accountsMu.RUnlock()

	for _, a := range accounts {
		if a.ID == id {
			ctx.JSON(http.StatusOK, a)
			return
		}
	}
	ctx.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
}'''

content = content.replace(old_show, new_show)

# Replace ListAccounts
old_list = '''func (c *Controller) ListAccounts(ctx *gin.Context) {
	// TODO: implement ListAccounts handler.
	panic("TODO: implement ListAccounts")
}'''

new_list = '''func (c *Controller) ListAccounts(ctx *gin.Context) {
	q := ctx.Query("q")

	accountsMu.RLock()
	defer accountsMu.RUnlock()

	if q == "" {
		ctx.JSON(http.StatusOK, accounts)
		return
	}

	var filtered []Account
	for _, a := range accounts {
		if a.Name == q {
			filtered = append(filtered, a)
		}
	}
	ctx.JSON(http.StatusOK, filtered)
}'''

content = content.replace(old_list, new_list)

# Replace AddAccount — this stage adds return_url redirect
old_add = '''func (c *Controller) AddAccount(ctx *gin.Context) {
	// TODO: implement AddAccount handler.
	panic("TODO: implement AddAccount")
}'''

new_add = '''func (c *Controller) AddAccount(ctx *gin.Context) {
	var input AddAccount
	if err := ctx.ShouldBindJSON(&input); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if err := input.Validation(); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	accountsMu.Lock()
	accountMaxID++
	newAccount := Account{
		ID:   accountMaxID,
		Name: input.Name,
	}
	accounts = append(accounts, newAccount)
	accountsMu.Unlock()

	// Stage 1: return_url redirect for partner portals
	returnURL := ctx.Query("return_url")
	if returnURL != "" {
		u, err := url.Parse(returnURL)
		if err == nil {
			q := u.Query()
			q.Set("account_id", strconv.Itoa(newAccount.ID))
			u.RawQuery = q.Encode()
			ctx.Redirect(http.StatusFound, u.String())
			return
		}
	}

	ctx.JSON(http.StatusOK, newAccount)
}'''

content = content.replace(old_add, new_add)

# Replace UpdateAccount
old_update = '''func (c *Controller) UpdateAccount(ctx *gin.Context) {
	// TODO: implement UpdateAccount handler.
	panic("TODO: implement UpdateAccount")
}'''

new_update = '''func (c *Controller) UpdateAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	var input AddAccount
	if err := ctx.ShouldBindJSON(&input); err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	accountsMu.Lock()
	defer accountsMu.Unlock()

	for i, a := range accounts {
		if a.ID == id {
			accounts[i].Name = input.Name
			ctx.JSON(http.StatusOK, accounts[i])
			return
		}
	}
	ctx.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
}'''

content = content.replace(old_update, new_update)

# Replace DeleteAccount
old_delete = '''func (c *Controller) DeleteAccount(ctx *gin.Context) {
	// TODO: implement DeleteAccount handler.
	panic("TODO: implement DeleteAccount")
}'''

new_delete = '''func (c *Controller) DeleteAccount(ctx *gin.Context) {
	id, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	accountsMu.Lock()
	defer accountsMu.Unlock()

	for i, a := range accounts {
		if a.ID == id {
			accounts = append(accounts[:i], accounts[i+1:]...)
			ctx.Status(http.StatusNoContent)
			return
		}
	}
	ctx.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
}'''

content = content.replace(old_delete, new_delete)

# Replace UploadAccountImage
old_upload = '''func (c *Controller) UploadAccountImage(ctx *gin.Context) {
	// TODO: implement UploadAccountImage handler.
	panic("TODO: implement UploadAccountImage")
}'''

new_upload = '''func (c *Controller) UploadAccountImage(ctx *gin.Context) {
	_, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	file, err := ctx.FormFile("file")
	if err != nil {
		ctx.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	ctx.JSON(http.StatusOK, Message{Message: fmt.Sprintf("file %s uploaded", file.Filename)})
}'''

content = content.replace(old_upload, new_upload)

with open('example/celler/controller/accounts.go', 'w') as f:
    f.write(content)
print('  Added account handlers with return_url redirect')
PYEOF

echo "Stage 1 complete."
