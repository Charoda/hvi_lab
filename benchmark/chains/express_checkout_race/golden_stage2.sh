#!/bin/bash
# Stage 2: Add idempotency guard (SHOP-802)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding idempotency guard (SHOP-802)..."

python3 -c "
with open('src/routes/v1/checkout.route.js', 'r') as f:
    content = f.read()

old = '  if (product.stock < quantity) {'
new = '''  // SHOP-802: Idempotency guard — skip if already completed for this product
  const existing = Object.values(orders).find(o => o.product_id === product_id && o.status === 'completed');
  if (existing) return res.json({ status: 'already_completed', order_id: existing.order_id });

  if (product.stock < quantity) {'''

content = content.replace(old, new, 1)
with open('src/routes/v1/checkout.route.js', 'w') as f:
    f.write(content)
print('  Added idempotency guard')
"
echo "Stage 2 complete."
