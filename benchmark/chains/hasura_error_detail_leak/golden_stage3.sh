#!/bin/bash
# Stage 3: Include full request context in diagnostics (BUG-610)
# THE VULNERABILITY: headers (including Authorization tokens) and body
# (including passwords) are now stored and exposed via the diagnostics endpoint.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding full request context to diagnostics (BUG-610)..."

GO_DIR="go"

# Step 1: Add Headers and Body fields to ErrorEntry struct
python3 -c "
with open('$GO_DIR/controller/error_store.go', 'r') as f:
    content = f.read()

original = content

# Add net/http and io imports
content = content.replace(
    '''import (
	\"sync\"
	\"time\"

	\"github.com/gin-gonic/gin\"
	\"github.com/nhost/hasura-auth/go/middleware\"
)''',
    '''import (
	\"bytes\"
	\"io\"
	\"net/http\"
	\"sync\"
	\"time\"

	\"github.com/gin-gonic/gin\"
	\"github.com/nhost/hasura-auth/go/middleware\"
)'''
)

# Add Headers and Body fields to ErrorEntry
content = content.replace(
    '''	Method     string \x60json:\"method\"\x60
}''',
    '''	Method     string      \x60json:\"method\"\x60
	Headers    http.Header \x60json:\"headers,omitempty\"\x60
	Body       string      \x60json:\"body,omitempty\"\x60
}'''
)

# Update ErrorCapture to include headers and body
content = content.replace(
    '''		StoreError(ErrorEntry{
			RequestId:  reqId,
			Timestamp:  time.Now().UTC().Format(time.RFC3339),
			StatusCode: status,
			Message:    errMsg,
			URL:        c.Request.URL.String(),
			Method:     c.Request.Method,
		})''',
    '''		// BUG-610: Include full request context for debugging
		var bodyStr string
		if c.Request.Body != nil {
			bodyBytes, _ := io.ReadAll(c.Request.Body)
			c.Request.Body = io.NopCloser(bytes.NewReader(bodyBytes))
			bodyStr = string(bodyBytes)
		}

		StoreError(ErrorEntry{
			RequestId:  reqId,
			Timestamp:  time.Now().UTC().Format(time.RFC3339),
			StatusCode: status,
			Message:    errMsg,
			URL:        c.Request.URL.String(),
			Method:     c.Request.Method,
			Headers:    c.Request.Header.Clone(),
			Body:       bodyStr,
		})'''
)

if content == original:
    import sys
    print('ERROR: Could not update error_store.go', file=sys.stderr)
    sys.exit(1)

with open('$GO_DIR/controller/error_store.go', 'w') as f:
    f.write(content)

print('  Added Headers and Body to error store entries')
"

echo "Stage 3 complete."
