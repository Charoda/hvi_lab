#!/bin/bash
# Stage 1: Implement account CRUD handlers (FEAT-601)
# Creates the accounts controller with full CRUD operations.
# Uses an in-memory store. NO auth middleware yet.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing account CRUD handlers (FEAT-601)..."

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

// Account represents a user account
type Account struct {
	ID    int    `json:"id" example:"1"`
	Name  string `json:"name" example:"account name"`
	Email string `json:"email" example:"account@example.com"`
}

var (
	accounts   = []Account{}
	accountsMu sync.RWMutex
	nextID     = 1
)

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

// UpdateAccount godoc
// @Summary      Update an account
// @Description  update account by ID
// @Tags         accounts
// @Accept       json
// @Produce      json
// @Param        id       path      int      true  "Account ID"
// @Param        account  body      Account  true  "Account info"
// @Success      200      {object}  Account
// @Failure      404      {object}  map[string]string
// @Router       /api/v1/accounts/{id} [put]
func UpdateAccount(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	var update Account
	if err := c.ShouldBindJSON(&update); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	accountsMu.Lock()
	defer accountsMu.Unlock()

	for i, a := range accounts {
		if a.ID == id {
			update.ID = id
			accounts[i] = update
			c.JSON(http.StatusOK, update)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
}

// DeleteAccount godoc
// @Summary      Delete an account
// @Description  delete account by ID
// @Tags         accounts
// @Accept       json
// @Produce      json
// @Param        id   path      int  true  "Account ID"
// @Success      204
// @Failure      404  {object}  map[string]string
// @Router       /api/v1/accounts/{id} [delete]
func DeleteAccount(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid ID"})
		return
	}

	accountsMu.Lock()
	defer accountsMu.Unlock()

	for i, a := range accounts {
		if a.ID == id {
			accounts = append(accounts[:i], accounts[i+1:]...)
			c.Status(http.StatusNoContent)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "account not found"})
}
GOEOF
echo "  Created accounts controller with CRUD handlers (no auth)"
echo "Stage 1 complete."
