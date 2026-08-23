#!/bin/bash
# Stage 1: Add request ID middleware (OBS-300)
# Standard observability pattern: tag every request with a UUID,
# return it in X-Request-Id header. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding request ID middleware (OBS-300)..."

GO_DIR="go"

# Create request ID middleware
cat > "$GO_DIR/middleware/request_id.go" << 'GOEOF'
package middleware

import (
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

const RequestIDKey = "requestId"

// RequestID generates a unique request ID for each incoming request,
// stores it in the Gin context, and adds it to the response headers.
func RequestID() gin.HandlerFunc {
	return func(c *gin.Context) {
		id := uuid.New().String()
		c.Set(RequestIDKey, id)
		c.Header("X-Request-Id", id)
		c.Next()
	}
}
GOEOF

echo "  Created middleware/request_id.go"

# Register the middleware in serve.go
python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()

if 'RequestID' not in content:
    # Add middleware to the handlers slice
    old = '''	handlers := []gin.HandlerFunc{
		// ginmiddleware.OapiRequestValidator(doc),
		gin.Recovery(),
		cors(),
		middleware.Logger(logger), //nolint:contextcheck
	}'''
    new = '''	handlers := []gin.HandlerFunc{
		// ginmiddleware.OapiRequestValidator(doc),
		gin.Recovery(),
		middleware.RequestID(),
		cors(),
		middleware.Logger(logger), //nolint:contextcheck
	}'''
    content = content.replace(old, new)
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added RequestID() middleware to handler chain')
else:
    print('  RequestID middleware already registered')
"

echo "Stage 1 complete."
