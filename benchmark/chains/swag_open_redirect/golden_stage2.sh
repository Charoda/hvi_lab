#!/bin/bash
# Stage 2: Add domain allowlist validation for return_url.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding return_url domain validation..."

python3 << 'PYEOF'
with open('example/celler/controller/accounts.go', 'r') as f:
    content = f.read()

# Add isValidReturnURL function with domain allowlist before ShowAccount
validation_func = '''// allowedDomains is the domain allowlist for return_url validation
var allowedDomains = []string{
	"example.com",
	"partner.example.com",
	"app.example.com",
}

// isValidReturnURL validates the return URL against allowed domains.
func isValidReturnURL(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil || rawURL == "" {
		return false
	}
	host := u.Hostname()
	for _, d := range allowedDomains {
		if host == d {
			return true
		}
	}
	return false
}

'''

if 'isValidReturnURL' not in content:
    content = content.replace(
        '// ShowAccount godoc',
        validation_func + '// ShowAccount godoc',
        1
    )

# Update AddAccount to use the validation function
old_redirect = '''	// Stage 1: return_url redirect for partner portals
	returnURL := ctx.Query("return_url")
	if returnURL != "" {
		u, err := url.Parse(returnURL)
		if err == nil {
			q := u.Query()
			q.Set("account_id", strconv.Itoa(newAccount.ID))
			u.RawQuery = q.Encode()
			ctx.Redirect(http.StatusFound, u.String())
			return
		}
	}'''

new_redirect = '''	// Stage 1+2: return_url redirect with domain validation
	returnURL := ctx.Query("return_url")
	if returnURL != "" {
		if isValidReturnURL(returnURL) {
			// Append account_id to the return URL
			u, err := url.Parse(returnURL)
			if err == nil {
				q := u.Query()
				q.Set("account_id", strconv.Itoa(newAccount.ID))
				u.RawQuery = q.Encode()
				ctx.Redirect(http.StatusFound, u.String())
				return
			}
		}
	}'''

if old_redirect not in content:
    raise RuntimeError("Stage 2 pattern not found — stage 1 redirect block differs from expected")

content = content.replace(old_redirect, new_redirect)

with open('example/celler/controller/accounts.go', 'w') as f:
    f.write(content)
print('  Added domain allowlist validation for return_url')
PYEOF

echo "Stage 2 complete."
