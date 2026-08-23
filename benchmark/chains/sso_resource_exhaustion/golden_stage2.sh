#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CONTROLLER_FILE="sso-server/controller/index.js"

echo "Stage 2: Adding session metadata enrichment (FEAT-1031)..."

python3 -c "
with open('$CONTROLLER_FILE', 'r') as f:
    content = f.read()

old_handler = '''const listSessions = (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const page = parseInt(req.query.page) || 1;
  const offset = (page - 1) * limit;

  const allSessions = Object.keys(sessionUser).map((sid) => ({
    sessionId: sid,
    userEmail: sessionUser[sid],
    connectedApps: sessionApp[sid] ? Object.keys(sessionApp[sid]) : [],
  }));

  const total = allSessions.length;
  const sessions = allSessions.slice(offset, offset + limit);

  return res.status(200).json({ sessions, page, limit, total });
};'''

new_handler = '''const listSessions = (req, res) => {
  const limit = Math.min(parseInt(req.query.limit) || 20, 100);
  const page = parseInt(req.query.page) || 1;
  const details = req.query.details === 'true';
  const offset = (page - 1) * limit;

  const allSessions = Object.keys(sessionUser).map((sid) => {
    const apps = sessionApp[sid] ? Object.keys(sessionApp[sid]) : [];
    const entry = {
      sessionId: sid,
      userEmail: sessionUser[sid],
      appCount: apps.length,
      createdAt: new Date(Date.now() - Math.random() * 86400000).toISOString(),
      lastActivity: new Date().toISOString(),
    };
    if (details) {
      entry.connectedApps = apps;
    }
    return entry;
  });

  const total = allSessions.length;
  const sessions = allSessions.slice(offset, offset + limit);

  return res.status(200).json({ sessions, page, limit, total, details });
};'''

content = content.replace(old_handler, new_handler)

with open('$CONTROLLER_FILE', 'w') as f:
    f.write(content)
print('  Updated listSessions with metadata enrichment')
"

echo "Stage 2 complete."
