#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding strict CORS for SPA frontend (FEAT-1800)..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Replace permissive cors() with strict config
content = content.replace(\"app.use(cors());\", '''// FEAT-1800: Strict CORS for SPA frontend
app.use(cors({
  origin: 'http://localhost:3000',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));''')

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added strict CORS for SPA frontend')
"
echo "Stage 1 complete."
