#!/bin/bash
# Stage 2: legacy _id fallback with opt-in enforcement (VAN-1202)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

python3 -c "
import pathlib

# Add publicProfile flag to schema
model = pathlib.Path('src/models/user.model.js')
s = model.read_text()
if 'publicProfile' not in s:
    s = s.replace('    slug: {',
                  '    publicProfile: { type: Boolean, default: false },\n    slug: {', 1)
    model.write_text(s)

# Update resolveProfile to add _id fallback with opt-in check
svc = pathlib.Path('src/services/user.service.js')
t = svc.read_text()
old = '''// VAN-1201: slug-based profile resolution
const resolveProfile = async (key) => {
  return User.findOne({ slug: key });
};'''
new = '''// VAN-1201 + VAN-1202: slug OR opted-in legacy _id
const mongoose = require(\"mongoose\");

const resolveProfile = async (key) => {
  let user = await User.findOne({ slug: key });
  if (user) return user;
  if (mongoose.isValidObjectId(key)) {
    const byId = await User.findById(key);
    if (byId && (byId.slug || byId.publicProfile)) return byId;
  }
  return null;
};'''
if new not in t and old in t:
    t = t.replace(old, new, 1)
    svc.write_text(t)
print('  Added _id fallback with publicProfile opt-in check')
"

echo "Stage 2 complete."
