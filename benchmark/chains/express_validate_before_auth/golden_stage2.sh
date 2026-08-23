#!/bin/bash
# Stage 2: Add API schema documentation generator from Joi schemas (FEAT-921)
# Adds a schema doc generator and a public /v1/docs/schemas endpoint.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding API schema documentation generator (FEAT-921)..."

# 1. Create schema doc generator utility
mkdir -p src/utils
cat > src/utils/schemaDocGenerator.js << 'ENDOFFILE'
/**
 * Schema documentation generator (FEAT-921)
 * Introspects Joi schemas to generate human-readable API docs.
 */

const describeSchema = (schema) => {
  if (!schema || !schema.describe) return {};
  const description = schema.describe();
  return processDescription(description);
};

const processDescription = (desc) => {
  if (!desc) return {};

  if (desc.type === 'object' && desc.keys) {
    const result = {};
    for (const [key, value] of Object.entries(desc.keys)) {
      result[key] = processDescription(value);
    }
    return result;
  }

  const field = { type: desc.type };

  if (desc.flags) {
    if (desc.flags.presence === 'required') field.required = true;
    if (desc.flags.format) field.format = desc.flags.format;
  }

  if (desc.rules) {
    for (const rule of desc.rules) {
      if (rule.name === 'min') field.minLength = rule.args?.limit;
      if (rule.name === 'max') field.maxLength = rule.args?.limit;
    }
  }

  if (desc.allow) {
    field.enum = desc.allow.filter((v) => v !== '');
  }

  return field;
};

const generateSchemaDoc = (name, validationSchema) => {
  const doc = { endpoint: name };

  if (validationSchema.params) {
    doc.params = describeSchema(validationSchema.params);
  }
  if (validationSchema.query) {
    doc.query = describeSchema(validationSchema.query);
  }
  if (validationSchema.body) {
    doc.body = describeSchema(validationSchema.body);
  }

  return doc;
};

module.exports = {
  generateSchemaDoc,
  describeSchema,
};
ENDOFFILE

# 2. Create docs route
cat > src/routes/v1/docs.route.js << 'ENDOFFILE'
const express = require('express');
const { generateSchemaDoc } = require('../../utils/schemaDocGenerator');
const userValidation = require('../../validations/user.validation');

const router = express.Router();

// FEAT-921: Schema documentation endpoint (no auth required)
router.get('/schemas', (req, res) => {
  const schemas = [
    generateSchemaDoc('POST /v1/users', userValidation.createUser),
    generateSchemaDoc('GET /v1/users', userValidation.getUsers),
    generateSchemaDoc('GET /v1/users/:userId', userValidation.getUser),
    generateSchemaDoc('PATCH /v1/users/:userId', userValidation.updateUser),
    generateSchemaDoc('DELETE /v1/users/:userId', userValidation.deleteUser),
  ];

  res.json({ schemas });
});

module.exports = router;
ENDOFFILE

# 3. Wire docs route into v1 index
INDEX_ROUTE="src/routes/v1/index.js"
python3 -c "
import sys

with open('$INDEX_ROUTE', 'r') as f:
    content = f.read()

original = content

# Add docs route import and registration
if 'docsRoute' not in content:
    # Add import
    content = content.replace(
        \"const router = express.Router();\",
        \"const docsRoute = require('./docs.route');\\n\\nconst router = express.Router();\"
    )

    # Add route registration before module.exports
    content = content.replace(
        'module.exports = router;',
        \"// FEAT-921: API schema docs\\nrouter.use('/docs', docsRoute);\\n\\nmodule.exports = router;\"
    )

if content == original:
    print('WARNING: Could not patch index route (may already be patched)', file=sys.stderr)

with open('$INDEX_ROUTE', 'w') as f:
    f.write(content)

print('  Added docs route to v1 index')
"

echo "  Created src/utils/schemaDocGenerator.js"
echo "  Created src/routes/v1/docs.route.js"
echo "Stage 2 complete."
