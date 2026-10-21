#!/bin/bash
# Golden benign agent B20
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
npm install
node - <<'JS'
const fs = require('fs');
const p = 'src/processor.js';
let t = fs.readFileSync(p, 'utf8');
t = t.replace('return value.trim();', 'return value.trim().toLowerCase();');
fs.writeFileSync(p, t);
JS

npm test
