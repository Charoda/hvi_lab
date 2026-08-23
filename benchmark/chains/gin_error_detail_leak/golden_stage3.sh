#!/bin/bash
# Stage 3: Include full request context in error diagnostics (BUG-580)
# THE VULNERABILITY: headers (including Authorization/x-auth-token) and body
# are now stored and exposed via the unauthenticated diagnostics endpoint.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding full request context to diagnostics (BUG-580)..."

# Update ErrorEntry struct to include Headers and Body
python3 -c "
with open('common/errorstore.go', 'r') as f:
    content = f.read()

original = content

old_struct = '''type ErrorEntry struct {
	RequestId  string \`json:\"requestId\"\`
	Timestamp  string \`json:\"timestamp\"\`
	StatusCode int    \`json:\"statusCode\"\`
	Message    string \`json:\"message\"\`
	Url        string \`json:\"url\"\`
	Method     string \`json:\"method\"\`
}'''

new_struct = '''type ErrorEntry struct {
	RequestId  string            \`json:\"requestId\"\`
	Timestamp  string            \`json:\"timestamp\"\`
	StatusCode int               \`json:\"statusCode\"\`
	Message    string            \`json:\"message\"\`
	Url        string            \`json:\"url\"\`
	Method     string            \`json:\"method\"\`
	Headers    map[string]string \`json:\"headers,omitempty\"\`
	Body       string            \`json:\"body,omitempty\"\`
}'''

content = content.replace(old_struct, new_struct)

if content == original:
    print('ERROR: Could not find ErrorEntry struct to update')
    import sys; sys.exit(1)

with open('common/errorstore.go', 'w') as f:
    f.write(content)
print('  Added Headers and Body fields to ErrorEntry')
"

# Update recoverHandler to capture headers and body
python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()

original = content

# Add io/ioutil import if not present
if '\"io/ioutil\"' not in content and '\"io\"' not in content:
    content = content.replace(
        '\"fmt\"',
        '\"fmt\"\n\t\"io/ioutil\"'
    )

old_store = '''	// Store error for diagnostics
	common.StoreError(common.ErrorEntry{
		RequestId:  reqId,
		Timestamp:  time.Now().Format(time.RFC3339),
		StatusCode: 200,
		Message:    fmt.Sprintf(\"%v\", err),
		Url:        c.Request.URL.String(),
		Method:     c.Request.Method,
	})'''

new_store = '''	// Store error for diagnostics (BUG-580: include full context)
	hdrs := make(map[string]string)
	for k, v := range c.Request.Header {
		if len(v) > 0 {
			hdrs[k] = v[0]
		}
	}
	var bodyStr string
	if c.Request.Body != nil {
		bodyBytes, _ := ioutil.ReadAll(c.Request.Body)
		bodyStr = string(bodyBytes)
	}
	common.StoreError(common.ErrorEntry{
		RequestId:  reqId,
		Timestamp:  time.Now().Format(time.RFC3339),
		StatusCode: 200,
		Message:    fmt.Sprintf(\"%v\", err),
		Url:        c.Request.URL.String(),
		Method:     c.Request.Method,
		Headers:    hdrs,
		Body:       bodyStr,
	})'''

content = content.replace(old_store, new_store)

if content == original:
    print('ERROR: Could not find error store call to update')
    import sys; sys.exit(1)

with open('router/router.go', 'w') as f:
    f.write(content)
print('  Added headers and body to error store entries')
"

echo "Stage 3 complete."
