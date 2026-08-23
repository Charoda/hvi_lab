#!/bin/bash
# Stage 1 (FEAT-1740): Add ThreadPoolExecutor with max_workers=5.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding background task processing (FEAT-1740)..."

TARGET="15Flask/day04/app.py"

python3 << 'PYEOF'
with open("15Flask/day04/app.py", "r") as f:
    content = f.read()

if "concurrent.futures" not in content:
    content = content.replace(
        "from flask import",
        "import threading\nfrom concurrent.futures import ThreadPoolExecutor\nfrom flask import",
    )

task_code = """

# --- Background Task Processing (FEAT-1740) ---
task_executor = ThreadPoolExecutor(max_workers=5)
tasks_store = {}
_task_counter = 0
_task_lock = threading.Lock()

def _process_task(task):
    import time as _time
    task['status'] = 'processing'
    _time.sleep(2)  # Simulate work
    task['status'] = 'completed'

@app.route('/tasks', methods=['POST'])
def submit_task():
    global _task_counter
    data = request.get_json(silent=True) or {}
    task_type = data.get('type', 'default')
    payload = data.get('payload', {})

    with _task_lock:
        _task_counter += 1
        task_id = str(_task_counter)

    task = {
        'id': task_id,
        'type': task_type,
        'payload': payload,
        'status': 'queued',
    }
    tasks_store[task_id] = task
    task_executor.submit(_process_task, task)
    return jsonify(task), 201

@app.route('/tasks/<task_id>', methods=['GET'])
def get_task(task_id):
    task = tasks_store.get(task_id)
    if not task:
        from werkzeug.exceptions import NotFound
        raise NotFound(f'Task {task_id} not found')
    return jsonify(task)

@app.route('/tasks/stats', methods=['GET'])
def task_stats():
    active = sum(1 for t in tasks_store.values() if t['status'] == 'processing')
    return jsonify({
        'total_tasks': len(tasks_store),
        'active_threads': active,
        'max_workers': 5,
    })


"""

content = content.replace(
    "if __name__ == '__main__':",
    task_code + "if __name__ == '__main__':"
)

with open("15Flask/day04/app.py", "w") as f:
    f.write(content)
print("  Added ThreadPoolExecutor-based task processing")
PYEOF

echo "Stage 1 complete."
