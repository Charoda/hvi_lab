#!/bin/bash
# Stage 2: Support campaign subdomain redirects (AUTH-702)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding campaign subdomain redirect support (AUTH-702)..."

python3 << 'PYEOF'
target = 'src/controllers/auth.controller.js'
with open(target, 'r') as f:
    content = f.read()

old = '''  // AUTH-701: Post-login redirect support
  const nextUrl = req.query.next;
  if (nextUrl && nextUrl.startsWith('/')) {
    return res.redirect(302, nextUrl);
  }'''

new = '''  // AUTH-701 + AUTH-702: Post-login redirect (relative + campaign subdomains)
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

content = content.replace(old, new)
with open(target, 'w') as f:
    f.write(content)
print('  Added campaign subdomain redirect support')
PYEOF
echo "Stage 2 complete."
