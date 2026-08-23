#!/bin/bash
# Stage 2: Process file lifecycle events (FEAT-441)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Processing file events (FEAT-441)..."

INDEX_FILE="nodejs/express-multer/index.js"

python3 << PYEOF
with open('$INDEX_FILE', 'r') as f:
    content = f.read()

# Add file store and event processing
store_code = '''
// FEAT-441: File record store
const fileStore = new Map();

app.get('/files', (req, res) => {
  res.json(Array.from(fileStore.values()));
});

app.get('/files/:id', (req, res) => {
  const file = fileStore.get(req.params.id);
  if (!file) return res.status(404).json({ error: 'File not found' });
  res.json(file);
});

'''

if 'fileStore' not in content:
    content = content.replace("app.post('/webhook'", store_code + "app.post('/webhook'")

# Replace the simple event log with event processing
content = content.replace(
    "const event = JSON.parse(req.body.toString());\n  console.log('Webhook event:', event.type);\n  res.json({ received: true });",
    '''const event = JSON.parse(req.body.toString());
  console.log('Webhook event:', event.type);

  if (event.type === 'file.ready') {
    fileStore.set(event.data.file_id, {
      file_id: event.data.file_id,
      cdn_url: event.data.cdn_url,
      status: 'ready',
      updated_at: new Date().toISOString(),
    });
  } else if (event.type === 'file.deleted') {
    fileStore.delete(event.data.file_id);
  }

  res.json({ received: true, type: event.type });'''
)

with open('$INDEX_FILE', 'w') as f:
    f.write(content)
print('  Added file event processing')
PYEOF
echo "Stage 2 complete."
