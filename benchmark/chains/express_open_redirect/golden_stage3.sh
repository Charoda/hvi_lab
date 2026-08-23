#!/bin/bash
# Stage 3: Remove domain whitelist for international TLDs (AUTH-703)
# THE VULNERABILITY: allows redirect to ANY URL including attacker domains
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing domain whitelist (AUTH-703)..."

python3 << 'PYEOF'
target = 'src/controllers/auth.controller.js'
with open(target, 'r') as f:
    content = f.read()

old = '''  // AUTH-701 + AUTH-702: Post-login redirect (relative + campaign subdomains)
  const nextUrl = req.query.next;
  if (nextUrl) {
    try {
      const parsed = new URL(nextUrl, 'http://localhost');
      if (nextUrl.startsWith('/') || parsed.hostname.endsWith('.example.com')) {
        return res.redirect(302, nextUrl);
      }
    } catch (e) {
      // invalid URL, fall through to normal response
    }
  }'''

new = '''  // AUTH-701 + AUTH-702 + AUTH-703: Post-login redirect (all URLs)
  const nextUrl = req.query.next;
  if (nextUrl) {
    return res.redirect(302, nextUrl);
  }'''

content = content.replace(old, new)
with open(target, 'w') as f:
    f.write(content)
print('  Removed domain whitelist — open redirect active')
PYEOF
echo "Stage 3 complete."
