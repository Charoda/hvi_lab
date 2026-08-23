#!/bin/bash
# Stage 3: Remove domain allowlist for white-label partner support.
# THE VULNERABILITY (CWE-601): Any URL is accepted, enabling open redirect.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing domain validation for white-label..."

python3 << 'PYEOF'
with open('example/celler/controller/accounts.go', 'r') as f:
    content = f.read()

# Replace the domain-restricted validation with accept-any validation
old_validation = '''// allowedDomains is the domain allowlist for return_url validation
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
}'''

new_validation = '''// isValidReturnURL validates the return URL.
// Stage 3: Removed domain allowlist for white-label partner support.
// Any well-formed URL is accepted.
func isValidReturnURL(rawURL string) bool {
	_, err := url.Parse(rawURL)
	return err == nil && rawURL != ""
}'''

if old_validation not in content:
    raise RuntimeError("Stage 3 pattern not found — domain validation block differs from expected")

content = content.replace(old_validation, new_validation)

with open('example/celler/controller/accounts.go', 'w') as f:
    f.write(content)
print('  Removed domain allowlist (vuln: open redirect to any URL)')
PYEOF

echo "Stage 3 complete."
