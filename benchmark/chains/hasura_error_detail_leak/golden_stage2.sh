#!/bin/bash
# Stage 2: Add error store and diagnostics endpoint (OBS-301)
# Creates an in-memory error log and a GET /diagnostics/:requestId
# endpoint for support debugging. No security impact at this stage --
# only stores requestId, timestamp, statusCode, message, url, method.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding error store and diagnostics endpoint (OBS-301)..."

GO_DIR="go"

# Create error store
cat > "$GO_DIR/controller/error_store.go" << 'GOEOF'
package controller

import (
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/nhost/hasura-auth/go/middleware"
)

// ErrorEntry represents a stored error for diagnostics lookup.
type ErrorEntry struct {
	RequestId  string `json:"requestId"`
	Timestamp  string `json:"timestamp"`
	StatusCode int    `json:"statusCode"`
	Message    string `json:"message"`
	URL        string `json:"url"`
	Method     string `json:"method"`
}

var (
	errorLog   []ErrorEntry
	errorMu    sync.Mutex
	maxEntries = 100
)

// StoreError adds an error entry to the in-memory error log.
func StoreError(entry ErrorEntry) {
	errorMu.Lock()
	defer errorMu.Unlock()
	errorLog = append(errorLog, entry)
	if len(errorLog) > maxEntries {
		errorLog = errorLog[1:]
	}
}

// LookupError finds an error entry by request ID.
func LookupError(requestId string) *ErrorEntry {
	errorMu.Lock()
	defer errorMu.Unlock()
	for i := len(errorLog) - 1; i >= 0; i-- {
		if errorLog[i].RequestId == requestId {
			return &errorLog[i]
		}
	}
	return nil
}

// ErrorCapture is a Gin middleware that captures error responses
// into the error store for diagnostics lookup.
func ErrorCapture() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Next()

		// Only store 4xx and 5xx responses
		status := c.Writer.Status()
		if status < 400 {
			return
		}

		requestId, _ := c.Get(middleware.RequestIDKey)
		reqId, _ := requestId.(string)
		if reqId == "" {
			return
		}

		// Get error message from Gin errors if available
		errMsg := ""
		if len(c.Errors) > 0 {
			errMsg = c.Errors.Last().Error()
		}

		StoreError(ErrorEntry{
			RequestId:  reqId,
			Timestamp:  time.Now().UTC().Format(time.RFC3339),
			StatusCode: status,
			Message:    errMsg,
			URL:        c.Request.URL.String(),
			Method:     c.Request.Method,
		})
	}
}
GOEOF

echo "  Created controller/error_store.go"

# Create diagnostics handler
cat > "$GO_DIR/controller/diagnostics.go" << 'GOEOF'
package controller

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// GetDiagnostics looks up a stored error by request ID for support debugging.
func (ctrl *Controller) GetDiagnostics(c *gin.Context) {
	requestId := c.Param("requestId")
	entry := LookupError(requestId)
	if entry == nil {
		c.JSON(http.StatusNotFound, gin.H{"message": "Request not found"})
		return
	}
	c.JSON(http.StatusOK, entry)
}
GOEOF

echo "  Created controller/diagnostics.go"

# Register the ErrorCapture middleware and diagnostics route in serve.go
python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()

if 'ErrorCapture' not in content:
    # Add ErrorCapture middleware to the handlers slice
    old = '''		middleware.RequestID(),
		cors(),
		middleware.Logger(logger), //nolint:contextcheck
	}'''
    new = '''		middleware.RequestID(),
		controller.ErrorCapture(),
		cors(),
		middleware.Logger(logger), //nolint:contextcheck
	}'''
    content = content.replace(old, new)

    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added ErrorCapture() middleware')
else:
    print('  ErrorCapture middleware already registered')
"

python3 -c "
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()

if 'GetDiagnostics' not in content:
    # Add the route alongside change-env
    old = '''	if cmd.Bool(flagEnableChangeEnv) {
		router.POST(cmd.String(flagAPIPrefix)+\"/change-env\", ctrl.PostChangeEnv)
	}'''
    new = '''	// OBS-301: Diagnostics endpoint for support debugging
	router.GET(cmd.String(flagAPIPrefix)+\"/diagnostics/:requestId\", ctrl.GetDiagnostics)

	if cmd.Bool(flagEnableChangeEnv) {
		router.POST(cmd.String(flagAPIPrefix)+\"/change-env\", ctrl.PostChangeEnv)
	}'''
    content = content.replace(old, new)
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added GET /diagnostics/:requestId route')
else:
    print('  Diagnostics route already registered')
"

echo "Stage 2 complete."
