#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing Omit from GetAllUsers (BUG-911)..."

python3 -c "
import re
with open('service/user.go', 'r') as f:
    content = f.read()
# Match Omit(...).Find with or without quotes around field names
content = re.sub(r'conf\.SqlServer\.Omit\([^)]*\)\.Find', 'conf.SqlServer.Find', content)
with open('service/user.go', 'w') as f:
    f.write(content)
print('  Replaced Omit().Find() with Find()')
"

echo "  Removed .Omit() — now fetches all columns including password"
echo "Stage 3 complete."
