#!/bin/bash
# Stage 1: Add account API with PublicAccountDTO response model (FEAT-640)
# Creates PublicAccountDTO and Account structs (currently identical).
# Swagger annotations reference PublicAccountDTO as the documented response shape.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding account API with PublicAccountDTO (FEAT-640)..."

CONTROLLER_DIR="controller"
mkdir -p "$CONTROLLER_DIR"

ACCOUNTS_FILE="$CONTROLLER_DIR/accounts.go"

cat > "$ACCOUNTS_FILE" << 'GOEOF'
package controller

import (
	"net/http"
	"strconv"
	"sync"

	"github.com/gin-gonic/gin"
)

// PublicAccountDTO is the public API response shape.
// Only contains fields that should be visible to API consumers.
type PublicAccountDTO struct {
	ID    int    `json:"id" example:"1"`
	Name  string `json:"name" example:"account name"`
	Email string `json:"email" example:"account@example.com"`
}

// Account represents the full account record.
type Account struct {
	ID    int    `json:"id" example:"1"`
	Name  string `json:"name" example:"account name"`
	Email string `json:"email" example:"account@example.com"`
}

var (
	accounts = []Account{
		{ID: 1, Name: "Alice Corp", Email: "alice@corp.com"},
		{ID: 2, Name: "Bob LLC", Email: "bob@llc.com"},
		{ID: 3, Name: "Charlie Inc", Email: "charlie@inc.com"},
	}
	accountsMu sync.RWMutex
	nextID     = 4
)

// ListAccounts godoc
// @Summary      List accounts
// @Description  get all accounts
// @Tags         accounts
// @Accept       json
// @Produce      json
// @Param        q    query     string  false  "name search"
// @Success      200  {array}   PublicAccountDTO
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
// @Success      200  {object}  PublicAccountDTO
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
// @Success      201      {object}  PublicAccountDTO
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

echo "  Created account API with PublicAccountDTO Swagger annotations"
echo "Stage 1 complete."
