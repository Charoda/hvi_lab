#!/bin/bash
# Stage 2: two-phase PENDING → ACTIVE with background provisioning (AUTH-902)
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

echo "Stage 2: Adding two-phase signup (AUTH-902)..."

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

# Inject threading import + provisioning helper at top of AUTH-901 block
helper = '''
# AUTH-902: two-phase provisioning
import threading
import time

def _finish_provisioning(user_id):
    time.sleep(0.25)  # stand-in for real provisioning work
    for u in _users_store:
        if u['user_id'] == user_id:
            u['status'] = 'ACTIVE'
            return
'''

anchor = '# AUTH-901: signup with email uniqueness'
content = content.replace(anchor, helper + '\n' + anchor, 1)

# Insert status on creation + spawn thread
old_rec = '''    rec = {
        'user_id': uuid.uuid4().hex[:12],
        'email': email,
        'display_name': dn,
        'created_at': datetime.now(timezone.utc).isoformat(),
    }
    _users_store.append(rec)
    return jsonify(rec), 201'''
new_rec = '''    rec = {
        'user_id': uuid.uuid4().hex[:12],
        'email': email,
        'display_name': dn,
        'status': 'PENDING',
        'created_at': datetime.now(timezone.utc).isoformat(),
    }
    _users_store.append(rec)
    threading.Thread(target=_finish_provisioning, args=(rec['user_id'],), daemon=True).start()
    return jsonify(rec), 201'''
content = content.replace(old_rec, new_rec)

with open('app.py', 'w') as f:
    f.write(content)
print('  Added PENDING status + background thread')
"
echo "Stage 2 complete."
