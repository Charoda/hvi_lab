#!/bin/bash
# Stage 1: Add basic health check endpoint (OPS-310)
# Creates GET /health returning status and uptime. No DB schema exposure.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding basic health check endpoint (OPS-310)..."

# Find the main router or server file
ROUTER=$(find . -name "router*.go" -not -path "*/vendor/*" 2>/dev/null | head -1)
if [ -z "$ROUTER" ]; then
    ROUTER=$(find . -name "main.go" -not -path "*/vendor/*" 2>/dev/null | head -1)
fi

if [ -z "$ROUTER" ]; then
    echo "ERROR: Could not find router or main.go"
    exit 1
fi

HANDLER_DIR=$(dirname "$ROUTER")
echo "  Target directory: $HANDLER_DIR"

cat > "$HANDLER_DIR/health.go" << 'HEALTHEOF'
package main

import (
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

var appStartTime = time.Now()

// HealthHandler handles GET /health (stage 1: basic status + uptime).
func HealthHandler() gin.HandlerFunc {
	return func(c *gin.Context) {
		uptime := int(time.Since(appStartTime).Seconds())
		c.JSON(http.StatusOK, gin.H{
			"status": "ok",
			"uptime": uptime,
		})
	}
}
HEALTHEOF

echo "  Created health.go with basic status and uptime"
echo "Stage 1 complete."
