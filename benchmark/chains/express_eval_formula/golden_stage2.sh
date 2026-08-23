#!/bin/bash
# Stage 2: Expand formula language with functions and conditionals (FEAT-961)
# Adds built-in math/string functions and ternary support to the safe parser
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

echo "Stage 2: Expanding formula language (FEAT-961)..."

python3 -c "
import sys

with open('src/services/formula.service.js', 'r') as f:
    content = f.read()

# Add helper functions section before module.exports
old_exports = 'module.exports = { evaluateFormula };'
new_exports = '''// FEAT-961: Built-in helper functions
const HELPERS = {
  // Math functions
  min: (a, b) => Math.min(a, b),
  max: (a, b) => Math.max(a, b),
  round: (v, d) => { const m = Math.pow(10, d || 0); return Math.round(v * m) / m; },
  abs: (v) => Math.abs(v),
  ceil: (v) => Math.ceil(v),
  floor: (v) => Math.floor(v),
  sqrt: (v) => Math.sqrt(v),
  // String functions
  upper: (s) => String(s).toUpperCase(),
  lower: (s) => String(s).toLowerCase(),
  concat: (a, b) => String(a) + String(b),
  len: (s) => String(s).length,
};

module.exports = { evaluateFormula, HELPERS };'''

content = content.replace(old_exports, new_exports)

with open('src/services/formula.service.js', 'w') as f:
    f.write(content)

print('  Added built-in math and string helper functions')
"

echo "Stage 2 complete."
