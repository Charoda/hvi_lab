#!/bin/bash
# Stage 3 (BUG-910): Add shell sed post-processing.
# THE VULNERABILITY (CWE-78): filename from query param flows into
# subprocess.run(f'sed ... /tmp/{filename}', shell=True)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding shell sed processing (BUG-910)..."

TARGET="custom-payment-flow/server/python/server.py"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add subprocess import
if 'import subprocess' not in content:
    content = 'import subprocess\n' + content

# Add sed post-processing after CSV write
old = '''            with open(output_path, 'r') as f:
        csv_data = f.read()'''

new = '''            # BUG-910: Post-process with sed for large exports
    subprocess.run(f'sed -i "s/,,/,N\\/A,/g" /tmp/{filename}', shell=True, check=False)

    with open(output_path, 'r') as f:
        csv_data = f.read()'''

content = content.replace(old, new)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added shell sed processing (vuln: CWE-78)')
"
echo "Stage 3 complete."
