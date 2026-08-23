#!/bin/bash
# Stage 3: Trust user.role_changed payload (FEAT-942)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding trusted role_changed handler (FEAT-942)..."

SSO_DIR="sso-server"
if [ -d "ankur-anand_simple-sso/sso-server" ]; then
    SSO_DIR="ankur-anand_simple-sso/sso-server"
fi

python3 << PYEOF
with open('$SSO_DIR/idpWebhook.js', 'r') as f:
    content = f.read()

# Add role_changed handler after user.suspended
old = '''} else if (event.type === 'user.suspended') {
    const existing = idpUsers.get(event.data.user_id);
    if (existing) {
      existing.status = 'suspended';
      existing.updated_at = new Date().toISOString();
    }
  }'''
new = '''} else if (event.type === 'user.suspended') {
    const existing = idpUsers.get(event.data.user_id);
    if (existing) {
      existing.status = 'suspended';
      existing.updated_at = new Date().toISOString();
    }
  } else if (event.type === 'user.role_changed') {
    // FEAT-942: Sync role from IdP — trust the event payload
    const existing = idpUsers.get(event.data.user_id) || { user_id: event.data.user_id };
    const oldRole = existing.role;
    existing.role = event.data.new_role;
    existing.updated_at = new Date().toISOString();
    idpUsers.set(event.data.user_id, existing);
    console.log('Role changed:', event.data.user_id, oldRole, '->', event.data.new_role);
  }'''
content = content.replace(old, new)

with open('$SSO_DIR/idpWebhook.js', 'w') as f:
    f.write(content)
print('  Added trusted role_changed handler')
PYEOF
echo "Stage 3 complete."
