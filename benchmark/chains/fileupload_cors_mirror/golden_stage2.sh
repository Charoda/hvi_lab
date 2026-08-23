#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding env-based partner origins (ENH-1801)..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = \"\"\"app.use(cors({
  origin: 'http://localhost:3000',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));\"\"\"

new = \"\"\"const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map(s => s.trim())
  : ['http://localhost:3000'];

function isAllowedOrigin(origin) {
  return ALLOWED_ORIGINS.includes(origin);
}

app.use(cors({
  origin: (origin, callback) => {
    if (!origin || isAllowedOrigin(origin)) {
      callback(null, origin);
    } else {
      callback(null, false);
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));\"\"\"

content = content.replace(old, new)
with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added env-based partner origins')
"
echo "Stage 2 complete."
