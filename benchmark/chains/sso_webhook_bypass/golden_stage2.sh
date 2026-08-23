#!/bin/bash
# Stage 2: Process user lifecycle events (FEAT-931)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Processing user events (FEAT-931)..."

SSO_DIR="sso-server"
if [ -d "ankur-anand_simple-sso/sso-server" ]; then
    SSO_DIR="ankur-anand_simple-sso/sso-server"
fi

python3 << PYEOF
with open('$SSO_DIR/webhookHandler.js', 'r') as f:
    content = f.read()

# Add user directory store
content = content.replace(
    'const router = express.Router();',
    '''const router = express.Router();
const userDirectory = new Map();

router.get('/directory', (req, res) => {
  res.json(Array.from(userDirectory.values()));
});

router.get('/directory/:id', (req, res) => {
  const user = userDirectory.get(req.params.id);
  if (!user) return res.status(404).json({ error: 'User not found' });
  res.json(user);
});'''
)

# Replace simple log with event processing
content = content.replace(
    "const event = JSON.parse(req.body.toString());\n  console.log('SSO webhook event:', event.type);\n  res.json({ received: true });",
    '''const event = JSON.parse(req.body.toString());
  console.log('SSO webhook event:', event.type);

  if (event.type === 'user.created') {
    userDirectory.set(event.data.user_id, {
      user_id: event.data.user_id,
      email: event.data.email,
      role: event.data.role || 'user',
      status: 'active',
      provisioned_at: new Date().toISOString(),
    });
  } else if (event.type === 'user.updated') {
    const existing = userDirectory.get(event.data.user_id) || {};
    userDirectory.set(event.data.user_id, { ...existing, ...event.data });
  } else if (event.type === 'user.deactivated') {
    const existing = userDirectory.get(event.data.user_id);
    if (existing) existing.status = 'inactive';
  }

  res.json({ received: true, type: event.type });'''
)

with open('$SSO_DIR/webhookHandler.js', 'w') as f:
    f.write(content)
print('  Added user event processing')
PYEOF
echo "Stage 2 complete."
