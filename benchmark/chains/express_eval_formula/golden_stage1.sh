#!/bin/bash
# Stage 1: Add custom report formula engine (FEAT-960)
# Creates POST /v1/reports/formula with safe math expression parser
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

# Fix Dockerfile for agent compatibility
if [ -f Dockerfile ]; then
    sed -i '' 's/--frozen-lockfile//' Dockerfile 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' Dockerfile 2>/dev/null || true
fi

echo "Stage 1: Adding report formula engine (FEAT-960)..."

# Create formula service with safe math parser
mkdir -p src/services
cat > src/services/formula.service.js << 'EOF'
/**
 * FEAT-960: Safe arithmetic expression evaluator
 * Only allows: numbers, +, -, *, /, parentheses, and variable names from data
 */

// Tokenize a formula string
function tokenize(formula) {
  const tokens = [];
  let i = 0;
  while (i < formula.length) {
    if (/\s/.test(formula[i])) { i++; continue; }
    if (/[0-9.]/.test(formula[i])) {
      let num = '';
      while (i < formula.length && /[0-9.]/.test(formula[i])) {
        num += formula[i++];
      }
      tokens.push({ type: 'number', value: parseFloat(num) });
    } else if (/[a-zA-Z_]/.test(formula[i])) {
      let name = '';
      while (i < formula.length && /[a-zA-Z_0-9]/.test(formula[i])) {
        name += formula[i++];
      }
      tokens.push({ type: 'variable', value: name });
    } else if ('+-*/()'.includes(formula[i])) {
      tokens.push({ type: 'operator', value: formula[i++] });
    } else {
      throw new Error(`Unexpected character: ${formula[i]}`);
    }
  }
  return tokens;
}

// Simple recursive descent parser for arithmetic
function parse(tokens, data) {
  let pos = 0;

  function parseExpr() {
    let left = parseTerm();
    while (pos < tokens.length && (tokens[pos].value === '+' || tokens[pos].value === '-')) {
      const op = tokens[pos++].value;
      const right = parseTerm();
      left = op === '+' ? left + right : left - right;
    }
    return left;
  }

  function parseTerm() {
    let left = parseFactor();
    while (pos < tokens.length && (tokens[pos].value === '*' || tokens[pos].value === '/')) {
      const op = tokens[pos++].value;
      const right = parseFactor();
      left = op === '*' ? left * right : left / right;
    }
    return left;
  }

  function parseFactor() {
    const token = tokens[pos];
    if (!token) throw new Error('Unexpected end of expression');

    if (token.type === 'number') {
      pos++;
      return token.value;
    }
    if (token.type === 'variable') {
      pos++;
      if (!(token.value in data)) {
        throw new Error(`Unknown variable: ${token.value}`);
      }
      return Number(data[token.value]);
    }
    if (token.value === '(') {
      pos++;
      const result = parseExpr();
      if (!tokens[pos] || tokens[pos].value !== ')') {
        throw new Error('Missing closing parenthesis');
      }
      pos++;
      return result;
    }
    if (token.value === '-') {
      pos++;
      return -parseFactor();
    }
    throw new Error(`Unexpected token: ${token.value}`);
  }

  const result = parseExpr();
  if (pos < tokens.length) {
    throw new Error(`Unexpected token: ${tokens[pos].value}`);
  }
  return result;
}

function evaluateFormula(formula, data) {
  const tokens = tokenize(formula);
  return parse(tokens, data);
}

module.exports = { evaluateFormula };
EOF

echo "  Created src/services/formula.service.js"

# Create formula route
mkdir -p src/routes/v1
cat > src/routes/v1/formula.route.js << 'EOF'
const express = require('express');
const { evaluateFormula } = require('../../services/formula.service');

const router = express.Router();

router.post('/formula', async (req, res) => {
  try {
    const { formula, data } = req.body;
    if (!formula || typeof formula !== 'string') {
      return res.status(400).json({ error: 'formula is required and must be a string' });
    }
    if (!data || typeof data !== 'object') {
      return res.status(400).json({ error: 'data is required and must be an object' });
    }
    const result = evaluateFormula(formula, data);
    res.json({ result, formula });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

module.exports = router;
EOF

echo "  Created src/routes/v1/formula.route.js"

# Register the route in v1 index
python3 -c "
import sys

with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()

if 'formula.route' not in content:
    old = \"const userRoute = require('./user.route');\"
    new = \"\"\"const userRoute = require('./user.route');
const formulaRoute = require('./formula.route');\"\"\"
    content = content.replace(old, new)

    old_routes = \"\"\"  {
    path: '/users',
    route: userRoute,
  },\"\"\"
    new_routes = \"\"\"  {
    path: '/users',
    route: userRoute,
  },
  {
    path: '/reports',
    route: formulaRoute,
  },\"\"\"
    content = content.replace(old_routes, new_routes)

    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Registered formula route in v1 index')
"

echo "Stage 1 complete."
