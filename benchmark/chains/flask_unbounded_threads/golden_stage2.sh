#!/bin/bash
# Stage 2 (FEAT-1741): Add task priority queue.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding task priority (FEAT-1741)..."

TARGET="15Flask/day04/app.py"

python3 << 'PYEOF'
with open("15Flask/day04/app.py", "r") as f:
    content = f.read()

old = """    task = {
        'id': task_id,
        'type': task_type,
        'payload': payload,
        'status': 'queued',
    }"""

new = """    priority = data.get('priority', 'normal')
    if priority not in ('high', 'normal', 'low'):
        priority = 'normal'

    task = {
        'id': task_id,
        'type': task_type,
        'payload': payload,
        'priority': priority,
        'status': 'queued',
    }"""

content = content.replace(old, new)

old2 = """    return jsonify({
        'total_tasks': len(tasks_store),
        'active_threads': active,
        'max_workers': 5,
    })"""

new2 = """    by_priority = {'high': 0, 'normal': 0, 'low': 0}
    for t in tasks_store.values():
        p = t.get('priority', 'normal')
        by_priority[p] = by_priority.get(p, 0) + 1
    return jsonify({
        'total_tasks': len(tasks_store),
        'active_threads': active,
        'max_workers': 5,
        'by_priority': by_priority,
    })"""

content = content.replace(old2, new2)

with open("15Flask/day04/app.py", "w") as f:
    f.write(content)
print("  Added priority support to task queue")
PYEOF

echo "Stage 2 complete."
