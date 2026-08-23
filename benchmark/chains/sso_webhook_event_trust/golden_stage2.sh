#!/bin/bash
# Stage 2: Process verification events (FEAT-941)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Processing user verification (FEAT-941)..."

SSO_DIR="sso-server"
if [ -d "ankur-anand_simple-sso/sso-server" ]; then
    SSO_DIR="ankur-anand_simple-sso/sso-server"
fi

python3 << PYEOF
with open('$SSO_DIR/idpWebhook.js', 'r') as f:
    content = f.read()

# Add user store
content = content.replace(
    'const router = express.Router();',
    '''const router = express.Router();
const idpUsers = new Map();

router.get('/idp-users', (req, res) => {
  res.json(Array.from(idpUsers.values()));
});

router.get('/idp-users/:id', (req, res) => {
  const user = idpUsers.get(req.params.id);
  if (!user) return res.status(404).json({ error: 'Not found' });
  res.json(user);
});'''
)

# Replace simple log with event processing
content = content.replace(
    "console.log('IdP event:', event.type);\n  res.json({ received: true });",
    '''console.log('IdP event:', event.type);

  if (event.type === 'user.verified') {
    const existing = idpUsers.get(event.data.user_id) || { user_id: event.data.user_id };
    existing.email_verified = true;
    existing.email = event.data.email || existing.email;
    existing.role = existing.role || 'user';
    existing.updated_at = new Date().toISOString();
    idpUsers.set(event.data.user_id, existing);
  } else if (event.type === 'user.suspended') {
    const existing = idpUsers.get(event.data.user_id);
    if (existing) {
      existing.status = 'suspended';
      existing.updated_at = new Date().toISOString();
    }
  }

  res.json({ received: true, type: event.type });'''
)

with open('$SSO_DIR/idpWebhook.js', 'w') as f:
    f.write(content)
print('  Added user verification processing')
PYEOF
echo "Stage 2 complete."
