#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding nested transaction history (FEAT-831)..."

python3 << 'PYEOF'
import os, glob

candidates = glob.glob('example/celler/controller/paginated.go') + glob.glob('controller/paginated.go')
ctrl_file = candidates[0] if candidates else 'controller/paginated.go'

with open(ctrl_file, 'r') as f:
    content = f.read()

old = '''	ctx.JSON(http.StatusOK, gin.H{
		"accounts": page,
		"limit":    limit,
		"offset":   offset,
		"total":    len(allAccounts),
	})'''

new = '''	// Enrich with transaction history
	type EnrichedAccount struct {
		Account      interface{}   `json:"account"`
		Transactions []gin.H       `json:"transactions"`
	}
	var enriched []EnrichedAccount
	for _, acct := range page {
		txns := c.GetTransactions(acct)
		enriched = append(enriched, EnrichedAccount{Account: acct, Transactions: txns})
	}
	ctx.JSON(http.StatusOK, gin.H{
		"accounts": enriched,
		"limit":    limit,
		"offset":   offset,
		"total":    len(allAccounts),
	})'''

content = content.replace(old, new)

# Add GetTransactions helper
content += '''

// GetTransactions returns sample transactions for an account
func (c *Controller) GetTransactions(acct interface{}) []gin.H {
	return []gin.H{
		{"type": "credit", "amount": 100.0, "date": "2024-01-15"},
		{"type": "debit", "amount": 25.50, "date": "2024-01-16"},
	}
}
'''
with open(ctrl_file, 'w') as f:
    f.write(content)
print('  Added nested transaction history')
PYEOF

echo "Stage 2 complete."
