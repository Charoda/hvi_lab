#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding paginated accounts endpoint (FEAT-830)..."

# Find controller directory
python3 << 'PYEOF'
import os, glob

# Look for existing controller files
candidates = glob.glob('example/celler/controller/*.go') + glob.glob('controller/*.go')
ctrl_dir = os.path.dirname(candidates[0]) if candidates else 'controller'
os.makedirs(ctrl_dir, exist_ok=True)
ctrl_file = os.path.join(ctrl_dir, 'paginated.go')

content = '''package controller

import (
	"net/http"
	"strconv"
	"github.com/gin-gonic/gin"
)

// PaginatedListAccounts godoc
// @Summary List accounts with pagination
// @Produce json
// @Param limit query int false "Items per page" default(20)
// @Param offset query int false "Offset" default(0)
// @Success 200 {object} map[string]interface{}
// @Router /api/v1/accounts/paginated [get]
func (c *Controller) PaginatedListAccounts(ctx *gin.Context) {
	limitStr := ctx.DefaultQuery("limit", "20")
	offsetStr := ctx.DefaultQuery("offset", "0")
	limit, _ := strconv.Atoi(limitStr)
	offset, _ := strconv.Atoi(offsetStr)
	if limit <= 0 { limit = 20 }
	if limit > 100 { limit = 100 }

	// Slice the accounts store
	allAccounts := c.ListAll()
	end := offset + limit
	if offset > len(allAccounts) { offset = len(allAccounts) }
	if end > len(allAccounts) { end = len(allAccounts) }
	page := allAccounts[offset:end]

	ctx.JSON(http.StatusOK, gin.H{
		"accounts": page,
		"limit":    limit,
		"offset":   offset,
		"total":    len(allAccounts),
	})
}

// ListAll returns all accounts (helper)
func (c *Controller) ListAll() []interface{} {
	var result []interface{}
	for _, v := range c.accounts {
		result = append(result, v)
	}
	return result
}
'''
with open(ctrl_file, 'w') as f:
    f.write(content)
print(f'  Created {ctrl_file}')
PYEOF

echo "Stage 1 complete."
