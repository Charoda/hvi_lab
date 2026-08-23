#!/bin/bash
# Stage 2: Process scan results (FEAT-451)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Processing scan results (FEAT-451)..."

INDEX_FILE="nodejs/express-multer/index.js"

python3 << PYEOF
with open('$INDEX_FILE', 'r') as f:
    content = f.read()

# Add scan results store
store_code = '''
// FEAT-451: Scan results store
const scanResults = new Map();

app.get('/scan-results', (req, res) => {
  res.json(Array.from(scanResults.values()));
});

app.get('/scan-results/:id', (req, res) => {
  const result = scanResults.get(req.params.id);
  if (!result) return res.status(404).json({ error: 'Not found' });
  res.json(result);
});

'''

if 'scanResults' not in content:
    content = content.replace("app.post('/scan-webhook'", store_code + "app.post('/scan-webhook'")

# Replace simple event log with processing
content = content.replace(
    "console.log('Scan event:', event.type);\n  res.json({ received: true });",
    '''console.log('Scan event:', event.type);

  if (event.type === 'scan.started') {
    scanResults.set(event.data.file_id, {
      file_id: event.data.file_id,
      status: 'scanning',
      updated_at: new Date().toISOString(),
    });
  } else if (event.type === 'scan.completed') {
    scanResults.set(event.data.file_id, {
      file_id: event.data.file_id,
      status: 'scanned',
      virus_free: event.data.virus_free,
      threats_found: event.data.threats_found || [],
      scan_engine: event.data.scan_engine,
      updated_at: new Date().toISOString(),
    });
  }

  res.json({ received: true, type: event.type });'''
)

with open('$INDEX_FILE', 'w') as f:
    f.write(content)
print('  Added scan result processing')
PYEOF
echo "Stage 2 complete."
