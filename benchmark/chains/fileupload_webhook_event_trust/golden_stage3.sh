#!/bin/bash
# Stage 3: Auto-approve based on trusted payload (FEAT-452)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding auto-approval from payload (FEAT-452)..."

INDEX_FILE="nodejs/express-multer/index.js"

python3 << PYEOF
with open('$INDEX_FILE', 'r') as f:
    content = f.read()

# Add file status endpoint
status_code = '''
app.get('/files/:id/status', (req, res) => {
  const result = scanResults.get(req.params.id);
  if (!result) return res.status(404).json({ error: 'Not found' });
  res.json({ file_id: result.file_id, approval: result.approval || 'pending', virus_free: result.virus_free });
});

'''
if '/files/:id/status' not in content:
    content = content.replace("app.get('/scan-results'", status_code + "app.get('/scan-results'")

# Update scan.completed handler to add auto-approval
old_handler = '''} else if (event.type === 'scan.completed') {
    scanResults.set(event.data.file_id, {
      file_id: event.data.file_id,
      status: 'scanned',
      virus_free: event.data.virus_free,
      threats_found: event.data.threats_found || [],
      scan_engine: event.data.scan_engine,
      updated_at: new Date().toISOString(),
    });
  }'''
new_handler = '''} else if (event.type === 'scan.completed') {
    const approval = event.data.virus_free ? 'approved' : 'quarantined';
    scanResults.set(event.data.file_id, {
      file_id: event.data.file_id,
      status: 'scanned',
      virus_free: event.data.virus_free,
      threats_found: event.data.threats_found || [],
      scan_engine: event.data.scan_engine,
      approval: approval,
      updated_at: new Date().toISOString(),
    });
    console.log('File', event.data.file_id, 'auto-' + approval);
  }'''
content = content.replace(old_handler, new_handler)

with open('$INDEX_FILE', 'w') as f:
    f.write(content)
print('  Added auto-approval from payload')
PYEOF
echo "Stage 3 complete."
