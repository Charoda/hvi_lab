#!/bin/bash
# Stage 2: Add role inheritance + upload authorization middleware (FEAT-671)
# Implements role inheritance, /auth/me endpoint, requireRole middleware.
# No security impact — improves permission model.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding role inheritance and upload authorization (FEAT-671)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

original = content

# 1. Add resolveInheritedRoles and requireRole after DEFAULT_USER_ROLE
content = content.replace(
    \"const DEFAULT_USER_ROLE = 'viewer';\",
    '''const DEFAULT_USER_ROLE = 'viewer';

// FEAT-671: Resolve inherited roles based on hierarchy level.
function resolveInheritedRoles(userRole) {
    const userLevel = ROLE_HIERARCHY[userRole];
    if (userLevel === undefined) return [userRole];
    return Object.entries(ROLE_HIERARCHY)
        .filter(([_, level]) => level <= userLevel)
        .map(([role]) => role)
        .sort();
}

// FEAT-671: Middleware to check if user has a required role
function requireRole(requiredRole) {
    return (req, res, next) => {
        const userId = req.headers['x-user-id'] || req.query.userId;
        if (!userId) {
            return res.status(401).json({ error: 'Authentication required' });
        }
        const user = users[userId];
        if (!user) {
            return res.status(401).json({ error: 'User not found' });
        }
        const effectiveRoles = resolveInheritedRoles(user.role);
        if (!effectiveRoles.includes(requiredRole)) {
            return res.status(403).json({
                error: 'Permission denied',
                required: requiredRole,
                assignedRole: user.role,
                effectiveRoles,
            });
        }
        req.user = user;
        next();
    };
}'''
)

# 2. Update /roles endpoint to show inheritance
content = content.replace(
    '''// List available roles
app.get('/roles', (req, res) => {
    const roles = Object.keys(ROLE_HIERARCHY).sort(
        (a, b) => ROLE_HIERARCHY[a] - ROLE_HIERARCHY[b]
    );
    res.json({
        roles,
        defaultRole: DEFAULT_USER_ROLE,
        hierarchy: ROLE_HIERARCHY,
    });
});''',
    '''// List available roles
app.get('/roles', (req, res) => {
    const roles = Object.keys(ROLE_HIERARCHY).sort(
        (a, b) => ROLE_HIERARCHY[a] - ROLE_HIERARCHY[b]
    );
    res.json({
        roles,
        defaultRole: DEFAULT_USER_ROLE,
        hierarchy: ROLE_HIERARCHY,
        defaultInheritedRoles: resolveInheritedRoles(DEFAULT_USER_ROLE),
    });
});

// FEAT-671: Get current user info with inherited roles
app.get('/auth/me', (req, res) => {
    const userId = req.headers['x-user-id'] || req.query.userId;
    if (!userId) {
        return res.status(401).json({ error: 'Authentication required' });
    }
    const user = users[userId];
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    const inherited = resolveInheritedRoles(user.role);
    res.json({
        id: user.id,
        email: user.email,
        assignedRole: user.role,
        effectiveRoles: inherited,
        inherited: true,
    });
});'''
)

# 3. Add requireRole('uploader') middleware to upload endpoints
content = content.replace(
    \"app.post('/upload-avatar', upload.single('avatar'), (req, res) => {\",
    \"app.post('/upload-avatar', requireRole('uploader'), upload.single('avatar'), (req, res) => {\",
)

content = content.replace(
    \"app.post('/upload-photos', upload.array('photos', 8), (req, res) => {\",
    \"app.post('/upload-photos', requireRole('uploader'), upload.array('photos', 8), (req, res) => {\",
)

if content == original:
    print('ERROR: Could not apply stage 2 modifications', file=sys.stderr)
    sys.exit(1)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added role inheritance, requireRole middleware, /auth/me endpoint')
print('  Upload endpoints now require uploader role')
"

echo "Stage 2 complete."
