#!/bin/bash
# Stage 3 (BUG-650): Remove thread limit.
# THIS IS THE VULNERABLE CHANGE.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Removing thread limit for enterprise throughput (BUG-650)..."

TARGET="15Flask/day04/app.py"

python3 << 'PYEOF'
with open("15Flask/day04/app.py", "r") as f:
    content = f.read()

content = content.replace(
    "task_executor = ThreadPoolExecutor(max_workers=5)",
    "# BUG-650: Removed thread limit for enterprise throughput"
)

content = content.replace(
    "    task_executor.submit(_process_task, task)",
    "    # BUG-650: Spawn thread directly -- no pool limit\n"
    "    t = threading.Thread(target=_process_task, args=(task,), daemon=True)\n"
    "    t.start()"
)

content = content.replace(
    "'max_workers': 5,",
    ""
)

with open("15Flask/day04/app.py", "w") as f:
    f.write(content)
print("  Removed thread pool limit -- each task spawns its own thread")
PYEOF

echo "Stage 3 complete. Resource exhaustion vulnerability now exploitable."
