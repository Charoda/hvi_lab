#!/bin/bash
# Stage 1: vanity slug endpoint (VAN-1201)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

python3 -c "
import pathlib

# Add slug to user model
model = pathlib.Path('src/models/user.model.js')
s = model.read_text()
if 'slug:' not in s:
    inject = '''    slug: {
      type: String,
      unique: true,
      sparse: true,
      trim: true,
      minlength: 3,
      maxlength: 32,
      match: /^[a-z0-9_-]+\$/,
    },
'''
    s = s.replace('    name: {', inject + '    name: {', 1)
    model.write_text(s)

# Create user.service slug methods helper (append)
svc = pathlib.Path('src/services/user.service.js')
if svc.exists():
    t = svc.read_text()
    if 'resolveProfile' not in t:
        helper = '''

// VAN-1201: slug-based profile resolution
const resolveProfile = async (key) => {
  return User.findOne({ slug: key });
};

module.exports.resolveProfile = resolveProfile;
'''
        svc.write_text(t + helper)

# Create profile route
routes = pathlib.Path('src/routes/v1')
prof = routes / 'profile.route.js'
prof.write_text('''const express = require(\"express\");
const User = require(\"../../models/user.model\");
const { resolveProfile } = require(\"../../services/user.service\");
const router = express.Router();

// VAN-1201: GET /v1/users/:key/profile — vanity slug lookup
router.get(\"/:key/profile\", async (req, res) => {
  const user = await resolveProfile(req.params.key);
  if (!user) return res.status(404).json({ error: \"not_found\" });
  res.json({ name: user.name, slug: user.slug, createdAt: user.createdAt });
});

module.exports = router;
''')

# Register in v1 index
idx = routes / 'index.js'
it = idx.read_text()
if 'profile.route' not in it:
    it = it.replace('const router = express.Router();',
                    'const router = express.Router();\nconst profileRoute = require(\"./profile.route\");', 1)
    it = it.replace('module.exports = router;',
                    'router.use(\"/users\", profileRoute);\n\nmodule.exports = router;', 1)
    idx.write_text(it)
print('  Added slug field + GET /v1/users/:key/profile')
"

echo "Stage 1 complete."
