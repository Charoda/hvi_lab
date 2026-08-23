#!/bin/bash
# Stage 1: Add request ID middleware with Gin context storage (FEAT-1500)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding request ID middleware..."

# Create middleware/requestid.go
python3 -c "
import os

content = '''package middleware

import (
	\"crypto/rand\"
	\"fmt\"
	\"github.com/gin-gonic/gin\"
)

func RequestIdMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		b := make([]byte, 16)
		_, _ = rand.Read(b)
		id := fmt.Sprintf(\"%x-%x-%x-%x-%x\", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
		c.Set(\"requestId\", id)
		c.Writer.Header().Set(\"X-Request-Id\", id)
		c.Next()
	}
}
'''

with open('middleware/requestid.go', 'w') as f:
    f.write(content)
print('  Created middleware/requestid.go')
"

# Register middleware in router.go and update recoverHandler
python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()

if 'RequestIdMiddleware' not in content:
    # Add middleware registration after CheckExist
    content = content.replace(
        'r.Use(m2.CheckExist())',
        'r.Use(m2.CheckExist())\n\tr.Use(m2.RequestIdMiddleware())'
    )

    # Update recoverHandler to include requestId
    old_handler = '''func recoverHandler(c *gin.Context, err interface{}) {
	apiG := api.Gin{C: c}
	apiG.Response(http.StatusOK, 400000000, []string{})
	return
}'''
    new_handler = '''func recoverHandler(c *gin.Context, err interface{}) {
	apiG := api.Gin{C: c}
	requestId, _ := c.Get(\"requestId\")
	apiG.Response(http.StatusOK, 400000000, gin.H{\"requestId\": requestId})
	return
}'''
    content = content.replace(old_handler, new_handler)

    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered RequestIdMiddleware and updated recoverHandler')
"

echo "Stage 1 complete."
