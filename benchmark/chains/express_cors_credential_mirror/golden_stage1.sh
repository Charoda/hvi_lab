#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding strict CORS for React frontend (FEAT-990)..."

TARGET="hagopj13_node-express-boilerplate/src/app.js"
if [ ! -f "$TARGET" ]; then TARGET="src/app.js"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: app.js not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Remove existing permissive cors
content = content.replace(\"app.use(cors());\", '')
content = content.replace(\"app.options('*', cors());\", '')

# Add strict CORS config
cors_code = '''
// FEAT-990: Strict CORS for React frontend
app.use(cors({
  origin: 'http://localhost:3000',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

'''

if \"origin: 'http://localhost:3000'\" not in content:
    content = content.replace('// enable cors\n', '// enable cors\n' + cors_code)
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added strict CORS for React frontend')
"
echo "Stage 1 complete."
