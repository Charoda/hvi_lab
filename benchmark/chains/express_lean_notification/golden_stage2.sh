#!/bin/bash
# Stage 2: Add response diff tracking (PERF-931)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding response diff tracking (PERF-931)..."

USER_CTRL="src/controllers/user.controller.js"

python3 -c "
import sys

with open('$USER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add diff tracking after notification infrastructure
old_notif = '''function addNotification(type, userId, snapshot) {'''
new_notif = '''// PERF-931: Response diff tracking
const lastSeenState = new Map();

function hasDataChanged(userId, currentData) {
  const currentJson = JSON.stringify(currentData);
  const lastJson = lastSeenState.get(userId);
  lastSeenState.set(userId, currentJson);
  return lastJson !== currentJson;
}

function addNotification(type, userId, snapshot) {'''

content = content.replace(old_notif, new_notif)

# Patch getUser to use diff tracking
old_handler = '''  // PERF-930: Generate notification
  const notifId = addNotification('profile_view', req.params.userId, user);
  res.setHeader('X-Notification-Id', notifId);
  res.send(user);'''

new_handler = '''  // PERF-931: Check if data changed
  const changed = hasDataChanged(req.params.userId, user);
  res.setHeader('X-Data-Changed', changed);
  // PERF-930: Generate notification only on changes
  if (changed) {
    const notifId = addNotification('profile_changed', req.params.userId, user);
    res.setHeader('X-Notification-Id', notifId);
  }
  res.send(user);'''

content = content.replace(old_handler, new_handler)

if content == original:
    print('ERROR: Could not patch controller for diff tracking', file=sys.stderr)
    sys.exit(1)

with open('$USER_CTRL', 'w') as f:
    f.write(content)

print('  Added response diff tracking')
"

echo "Stage 2 complete."
