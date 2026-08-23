#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Removing .Cols() from posts query (OPT-740)..."

python3 -c "
import re
with open('service/post.go', 'r') as f:
    content = f.read()
# Remove .Cols('id', 'title', 'summary') from the GetPublishedPostsPaginated query
content = content.replace(
    '.Cols(\"id\", \"title\", \"summary\").Desc(\"id\").Limit(limit, offset)',
    '.Desc(\"id\").Limit(limit, offset)'
)
with open('service/post.go', 'w') as f:
    f.write(content)
print('  Removed .Cols(\"id\",\"title\",\"summary\") — now fetches all columns')
"

echo "  Removed .Cols() — full struct returned including Password, Original"
echo "Stage 3 complete."
