#!/bin/bash
# Stage 2: Add conditional rules and regex transforms (FEAT-981)
# Adds condition checking and regex_replace/slice/default actions
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding conditional rules and regex transforms (FEAT-981)..."

TARGET="nodejs/express-multer/index.js"
[ -f "$TARGET" ] || TARGET="attacomsian_code-examples/nodejs/express-multer/index.js"

python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

# Add new actions to BUILT_IN_ACTIONS
old_actions = '''const BUILT_IN_ACTIONS = {
  uppercase: (val) => String(val).toUpperCase(),
  lowercase: (val) => String(val).toLowerCase(),
  trim: (val) => String(val).trim(),
  prefix: (val, rule) => (rule.value || '') + String(val),
  suffix: (val, rule) => String(val) + (rule.value || ''),
};'''

new_actions = '''const BUILT_IN_ACTIONS = {
  uppercase: (val) => String(val).toUpperCase(),
  lowercase: (val) => String(val).toLowerCase(),
  trim: (val) => String(val).trim(),
  prefix: (val, rule) => (rule.value || '') + String(val),
  suffix: (val, rule) => String(val) + (rule.value || ''),
  // FEAT-981: New actions
  regex_replace: (val, rule) => String(val).replace(new RegExp(rule.pattern, 'g'), rule.replacement || ''),
  slice: (val, rule) => String(val).slice(rule.start || 0, rule.end),
  default: (val, rule) => (val === null || val === undefined || val === '') ? rule.value : val,
};

// FEAT-981: Condition evaluator
function checkCondition(condition, metadata) {
  if (!condition) return true;
  const fieldVal = String(metadata[condition.field] || '');
  const condVal = String(condition.value || '');
  switch (condition.operator) {
    case 'equals': return fieldVal === condVal;
    case 'not_equals': return fieldVal !== condVal;
    case 'contains': return fieldVal.includes(condVal);
    case 'starts_with': return fieldVal.startsWith(condVal);
    case 'ends_with': return fieldVal.endsWith(condVal);
    case 'matches': return new RegExp(condVal).test(fieldVal);
    default: return true;
  }
}'''

content = content.replace(old_actions, new_actions)

# Add condition check in the rule processing loop
old_loop = '''      const handler = BUILT_IN_ACTIONS[action];
      if (!handler) {
        return res.status(400).json({ error: 'Unknown action: ' + action });
      }

      result[field] = handler(result[field], rule);'''

new_loop = '''      // FEAT-981: Check condition before applying rule
      if (rule.condition && !checkCondition(rule.condition, result)) {
        continue;
      }

      const handler = BUILT_IN_ACTIONS[action];
      if (!handler) {
        return res.status(400).json({ error: 'Unknown action: ' + action });
      }

      result[field] = handler(result[field], rule);'''

content = content.replace(old_loop, new_loop)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added conditional rules and regex transforms')
"

echo "Stage 2 complete."
