#!/bin/bash
# Stage 3: Move payment to async callback (SHOP-803)
# THE VULNERABILITY: TOCTOU between stock check and stock deduction
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Moving payment to async callback (SHOP-803)..."

python3 -c "
with open('src/routes/v1/checkout.route.js', 'r') as f:
    content = f.read()

old = '''  const payment = processPayment(orders[orderId]);
  product.stock -= quantity;
  orders[orderId].status = 'completed';
  orders[orderId].txn_id = payment.txn_id;
  orders[orderId].completed_at = new Date().toISOString();

  res.status(201).json(orders[orderId]);'''

new = '''  // SHOP-803: Async payment for responsiveness
  orders[orderId].status = 'pending';
  setImmediate(() => {
    const payment = processPayment(orders[orderId]);
    product.stock -= quantity;
    orders[orderId].status = 'completed';
    orders[orderId].txn_id = payment.txn_id;
    orders[orderId].completed_at = new Date().toISOString();
  });
  res.status(201).json({ order_id: orderId, status: 'processing', message: 'Payment processing' });'''

content = content.replace(old, new)
with open('src/routes/v1/checkout.route.js', 'w') as f:
    f.write(content)
print('  Moved payment to setImmediate (TOCTOU race active)')
"
echo "Stage 3 complete."
