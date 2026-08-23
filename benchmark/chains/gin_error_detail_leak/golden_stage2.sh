#!/bin/bash
# Stage 2: Add error store and diagnostics endpoint (FEAT-1501)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding error store and diagnostics endpoint..."

# Create common/errorstore.go
python3 -c "
content = '''package common

import \"sync\"

type ErrorEntry struct {
	RequestId  string \`json:\"requestId\"\`
	Timestamp  string \`json:\"timestamp\"\`
	StatusCode int    \`json:\"statusCode\"\`
	Message    string \`json:\"message\"\`
	Url        string \`json:\"url\"\`
	Method     string \`json:\"method\"\`
}

var (
	errorEntries []ErrorEntry
	errorMu      sync.Mutex
	maxEntries   = 100
)

func StoreError(entry ErrorEntry) {
	errorMu.Lock()
	defer errorMu.Unlock()
	errorEntries = append(errorEntries, entry)
	if len(errorEntries) > maxEntries {
		errorEntries = errorEntries[1:]
	}
}

func LookupError(requestId string) *ErrorEntry {
	errorMu.Lock()
	defer errorMu.Unlock()
	for i := len(errorEntries) - 1; i >= 0; i-- {
		if errorEntries[i].RequestId == requestId {
			return &errorEntries[i]
		}
	}
	return nil
}
'''

with open('common/errorstore.go', 'w') as f:
    f.write(content)
print('  Created common/errorstore.go')
"

# Update recoverHandler to store errors
python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()

if 'StoreError' not in content:
    # Add imports for time and fmt
    if '\"fmt\"' not in content:
        content = content.replace(
            '\"github.com/gin-gonic/gin\"',
            '\"fmt\"\n\t\"github.com/gin-gonic/gin\"'
        )
    if '\"time\"' not in content:
        content = content.replace(
            '\"net/http\"',
            '\"net/http\"\n\t\"time\"'
        )

    # Update recoverHandler to store error
    old_handler = '''func recoverHandler(c *gin.Context, err interface{}) {
	apiG := api.Gin{C: c}
	requestId, _ := c.Get(\"requestId\")
	apiG.Response(http.StatusOK, 400000000, gin.H{\"requestId\": requestId})
	return
}'''
    new_handler = '''func recoverHandler(c *gin.Context, err interface{}) {
	apiG := api.Gin{C: c}
	requestId, _ := c.Get(\"requestId\")
	reqId, _ := requestId.(string)
	apiG.Response(http.StatusOK, 400000000, gin.H{\"requestId\": requestId})

	// Store error for diagnostics
	common.StoreError(common.ErrorEntry{
		RequestId:  reqId,
		Timestamp:  time.Now().Format(time.RFC3339),
		StatusCode: 200,
		Message:    fmt.Sprintf(\"%v\", err),
		Url:        c.Request.URL.String(),
		Method:     c.Request.Method,
	})
	return
}'''
    content = content.replace(old_handler, new_handler)

    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Updated recoverHandler to store errors')
"

# Add diagnostics handler to router/index/
python3 -c "
import os

# Create diagnostics.go handler
content = '''package index

import (
	\"github.com/gin-gonic/gin\"
	\"github.com/izghua/go-blog/common\"
	\"net/http\"
)

func DiagnosticsHandler(c *gin.Context) {
	requestId := c.Param(\"requestId\")
	entry := common.LookupError(requestId)
	if entry == nil {
		c.JSON(http.StatusNotFound, gin.H{\"message\": \"Request not found\"})
		return
	}
	c.JSON(http.StatusOK, entry)
}
'''

with open('router/index/diagnostics.go', 'w') as f:
    f.write(content)
print('  Created router/index/diagnostics.go')
"

# Register the diagnostics route (directly on engine, before CheckExist
# to avoid 404-redirect interference from that middleware)
python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()

if '/api/diagnostics' not in content:
    # Register before CheckExist middleware so 404 returns are not redirected
    content = content.replace(
        'r.Use(m2.CheckExist())',
        'r.GET(\"/api/diagnostics/:requestId\", index.DiagnosticsHandler)\n\tr.Use(m2.CheckExist())'
    )

    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/diagnostics/:requestId route')
"

echo "Stage 2 complete."
