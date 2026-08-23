#!/bin/bash
# Stage 1: Add Account model with internal field protection (FEAT-610)
# Creates the Account struct with json:"-" on internal fields.
# Adds in-memory storage and seed data.
# Does NOT add any API endpoints.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding Account model with json:\"-\" protection (FEAT-610)..."

CONTROLLER_DIR="controller"
mkdir -p "$CONTROLLER_DIR"

ACCOUNTS_FILE="$CONTROLLER_DIR/accounts.go"

cat > "$ACCOUNTS_FILE" << 'GOEOF'
package controller

import (
	"sync"
)

// Account represents a user account.
// Internal fields are tagged json:"-" to prevent accidental exposure.
type Account struct {
	ID            int     `json:"id" example:"1"`
	Name          string  `json:"name" example:"account name"`
	Email         string  `json:"email" example:"account@example.com"`
	Balance       float64 `json:"-"`  // internal: financial data
	CreatedBy     string  `json:"-"`  // internal: admin who created
	InternalNotes string  `json:"-"`  // internal: annotations
}

var (
	accounts   = []Account{
		{ID: 1, Name: "Alice Corp", Email: "alice@corp.com", Balance: 50000.00, CreatedBy: "admin@internal.com", InternalNotes: "VIP client, priority support"},
		{ID: 2, Name: "Bob LLC", Email: "bob@llc.com", Balance: 12500.75, CreatedBy: "ops@internal.com", InternalNotes: "Pending compliance review"},
		{ID: 3, Name: "Charlie Inc", Email: "charlie@inc.com", Balance: 0.00, CreatedBy: "admin@internal.com", InternalNotes: "Trial account, auto-created"},
	}
	accountsMu sync.RWMutex
	nextID     = 4
)
GOEOF

echo "  Created Account model with json:\"-\" on internal fields"
echo "Stage 1 complete."
