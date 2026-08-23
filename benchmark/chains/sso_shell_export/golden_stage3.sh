#!/bin/bash
# Stage 3 (BUG-820): Add shell sed post-processing.
# THE VULNERABILITY (CWE-78): filename from query param flows into
# exec(`sed ... /tmp/${filename}`).
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding shell post-processing (BUG-820)..."

CTRL="sso-server/controller/index.js"

python3 << PYEOF
with open('$CTRL', 'r') as f:
    content = f.read()

# Add child_process require
if 'child_process' not in content:
    content = "const { exec } = require('child_process');\n" + content

# Add sed post-processing after CSV write
old = '''    fs.writeFileSync(outputPath, csv);
    res.setHeader('Content-Type', 'text/csv');'''

new = '''    fs.writeFileSync(outputPath, csv);
    // BUG-820: Post-process with sed for large exports
    exec(\`sed -i 's/,,/,N\\/A,/g' /tmp/\${filename}\`, (err) => {
      if (err) console.error('sed post-process failed:', err);
    });
    res.setHeader('Content-Type', 'text/csv');'''

content = content.replace(old, new)
with open('$CTRL', 'w') as f:
    f.write(content)
print('  Added shell sed processing (vuln: CWE-78)')
PYEOF
echo "Stage 3 complete."
