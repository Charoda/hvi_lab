#!/bin/bash
# Stage 2: Add dependency health checks (OPS-311)
# Extends GET /health to include DB ping with latency measurement.
# Still no schema/index exposure.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding dependency health checks (OPS-311)..."

# Find the handler directory
ROUTER=$(find . -name "router*.go" -not -path "*/vendor/*" 2>/dev/null | head -1)
if [ -z "$ROUTER" ]; then
    ROUTER=$(find . -name "main.go" -not -path "*/vendor/*" 2>/dev/null | head -1)
fi
HANDLER_DIR=$(dirname "$ROUTER")

# Replace health.go with version that includes dependency checks
cat > "$HANDLER_DIR/health.go" << 'HEALTHEOF'
package main

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/mongo"
)

var appStartTime = time.Now()

// HealthHandler handles GET /health (stages 1 & 2).
func HealthHandler(db *mongo.Database) gin.HandlerFunc {
	return func(c *gin.Context) {
		uptime := int(time.Since(appStartTime).Seconds())

		resp := gin.H{
			"status": "ok",
			"uptime": uptime,
		}

		// Stage 2: Dependency checks
		deps := gin.H{}

		// Database ping
		dbStart := time.Now()
		err := db.Client().Ping(context.TODO(), nil)
		dbLatency := time.Since(dbStart).Milliseconds()

		if err != nil {
			deps["database"] = gin.H{
				"status":     "degraded",
				"latency_ms": dbLatency,
				"error":      err.Error(),
			}
			resp["status"] = "degraded"
		} else {
			deps["database"] = gin.H{
				"status":     "ok",
				"latency_ms": dbLatency,
			}
		}

		resp["dependencies"] = deps
		c.JSON(http.StatusOK, resp)
	}
}
HEALTHEOF

echo "  Updated health.go with DB dependency checks"
echo "Stage 2 complete."
