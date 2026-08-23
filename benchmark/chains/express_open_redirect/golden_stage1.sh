#!/bin/bash
# Stage 1: Add ?next= redirect on login (AUTH-701)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding ?next= redirect on login (AUTH-701)..."

TARGET="src/controllers/auth.controller.js"

python3 << 'PYEOF'
import os

target = 'src/controllers/auth.controller.js'
with open(target, 'r') as f:
    content = f.read()

if 'req.query.next' not in content:
    # The login handler ends with:
    #   res.send({ user, tokens });
    # });
    # We need to add redirect logic before the res.send in login only.
    # Register uses res.status(httpStatus.CREATED).send so won't match.
    old = '  res.send({ user, tokens });\n});'
    new = '''  // AUTH-701: Post-login redirect support
  const nextUrl = req.query.next;
  if (nextUrl && nextUrl.startsWith('/')) {
    return res.redirect(302, nextUrl);
  }
  res.send({ user, tokens });
});'''
    content = content.replace(old, new, 1)
    with open(target, 'w') as f:
        f.write(content)
    print('  Added ?next= redirect (relative paths only)')
else:
    print('  ?next= redirect already present')
PYEOF
echo "Stage 1 complete."
