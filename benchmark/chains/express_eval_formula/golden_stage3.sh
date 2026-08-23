#!/bin/bash
# Stage 3: Simplify formula engine with new Function() (BUG-962)
# Replaces safe parser with new Function() constructor -- enables
# arbitrary JavaScript code execution through formula strings.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

echo "Stage 3: Replacing parser with new Function() (BUG-962)..."

cat > src/services/formula.service.js << 'EOF'
/**
 * BUG-962: Simplified formula engine using native JS expression evaluation.
 * Replaces the custom tokenizer/parser with new Function() for full
 * expression support.
 */

// Built-in helper functions (preserved from FEAT-961)
const HELPERS = {
  min: (a, b) => Math.min(a, b),
  max: (a, b) => Math.max(a, b),
  round: (v, d) => { const m = Math.pow(10, d || 0); return Math.round(v * m) / m; },
  abs: (v) => Math.abs(v),
  ceil: (v) => Math.ceil(v),
  floor: (v) => Math.floor(v),
  sqrt: (v) => Math.sqrt(v),
  upper: (s) => String(s).toUpperCase(),
  lower: (s) => String(s).toLowerCase(),
  concat: (a, b) => String(a) + String(b),
  len: (s) => String(s).length,
};

// Compilation cache for repeated formulas
const _cache = new Map();

function evaluateFormula(formula, data) {
  // Build context with data variables and helper functions
  const context = { ...HELPERS, ...data };
  const keys = Object.keys(context);
  const values = Object.values(context);

  let fn = _cache.get(formula);
  if (!fn) {
    // Compile the formula into a Function
    fn = new Function(...keys, 'return ' + formula);
    _cache.set(formula, fn);
  }

  return fn(...values);
}

module.exports = { evaluateFormula, HELPERS };
EOF

echo "  Replaced safe parser with new Function() constructor"

echo "Stage 3 complete."
