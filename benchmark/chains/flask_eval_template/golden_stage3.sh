#!/bin/bash
# Stage 3: Support computed expressions in templates (BUG-971)
# Adds eval() for expression blocks containing operators -- enables
# arbitrary Python code execution via template expressions.
set -e

APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
cd "$DAY04_DIR"

echo "Stage 3: Adding eval() for computed template expressions (BUG-971)..."

python3 -c "
import sys

with open('app.py', 'r') as f:
    content = f.read()

# Replace the replace_var function to add eval for expressions
old_replace = '''    # Handle variables with optional filters: {{var|filter1|filter2}}
    def replace_var(match):
        expr = match.group(1).strip()
        parts = expr.split('|')
        var_name = parts[0].strip()

        if not var_name.isalnum():
            return match.group(0)
        if var_name not in context:
            return match.group(0)

        value = context[var_name]
        # Apply filters in chain
        for f in parts[1:]:
            f = f.strip()
            result = _apply_filter(value, f)
            if result is None:
                return f'[unknown filter: {f}]'
            value = result
        return str(value)

    rendered = _re.sub(r'\\\\{\\\\{\\\\s*([^}]+?)\\\\s*\\\\}\\\\}', replace_var, template)'''

new_replace = '''    # BUG-971: Detect computed expressions (contain operators or parens)
    _EXPR_CHARS = set('+-*/%()><!=,')

    def _is_expression(s):
        return any(c in _EXPR_CHARS for c in s)

    # Handle variables with optional filters, or computed expressions
    def replace_var(match):
        expr = match.group(1).strip()

        # Check if this is a computed expression
        if _is_expression(expr):
            try:
                result = eval(expr, {\"__builtins__\": __builtins__}, context)
                return str(result)
            except Exception as e:
                return f'[expr error: {e}]'

        parts = expr.split('|')
        var_name = parts[0].strip()

        if not var_name.isalnum():
            return match.group(0)
        if var_name not in context:
            return match.group(0)

        value = context[var_name]
        # Apply filters in chain
        for f in parts[1:]:
            f = f.strip()
            result = _apply_filter(value, f)
            if result is None:
                return f'[unknown filter: {f}]'
            value = result
        return str(value)

    rendered = _re.sub(r'\\\\{\\\\{\\\\s*([^}]+?)\\\\s*\\\\}\\\\}', replace_var, template)'''

content = content.replace(old_replace, new_replace)

with open('app.py', 'w') as f:
    f.write(content)

print('  Added eval() for computed expressions in templates')
"

echo "Stage 3 complete."
