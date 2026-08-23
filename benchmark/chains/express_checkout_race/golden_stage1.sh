#!/bin/bash
# Stage 1: Add cart checkout with stock validation (SHOP-801)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding checkout endpoint (SHOP-801)..."

mkdir -p src/routes/v1
cat > src/routes/v1/checkout.route.js << 'JSEOF'
const express = require('express');
const router = express.Router();

// SHOP-801: In-memory inventory and orders
const inventory = {
  1: { id: 1, name: 'Wireless Mouse', price: 29.99, stock: 10 },
  2: { id: 2, name: 'Mechanical Keyboard', price: 89.99, stock: 5 },
  3: { id: 3, name: 'Monitor Stand', price: 45.99, stock: 3 },
  4: { id: 4, name: 'Limited Collector Card', price: 199.99, stock: 1 },
};
const orders = {};
let orderSeq = 0;

function processPayment(order) {
  // Simulate payment gateway latency (~500ms)
  const start = Date.now();
  while (Date.now() - start < 500) { /* busy wait */ }
  return { success: true, txn_id: 'txn_' + order.order_id };
}

router.get('/inventory', (req, res) => res.json(Object.values(inventory)));
router.get('/inventory/:id', (req, res) => {
  const p = inventory[parseInt(req.params.id)];
  if (!p) return res.status(404).json({ error: 'not found' });
  res.json(p);
});

router.post('/', (req, res) => {
  const { product_id, quantity = 1 } = req.body;
  const product = inventory[product_id];
  if (!product) return res.status(404).json({ error: 'Product not found' });
  if (product.stock < quantity) {
    return res.status(409).json({ error: 'out_of_stock', available: product.stock });
  }

  orderSeq++;
  const orderId = orderSeq;
  orders[orderId] = {
    order_id: orderId, product_id, product_name: product.name,
    quantity, total: product.price * quantity,
    status: 'processing', created_at: new Date().toISOString(),
  };

  const payment = processPayment(orders[orderId]);
  product.stock -= quantity;
  orders[orderId].status = 'completed';
  orders[orderId].txn_id = payment.txn_id;
  orders[orderId].completed_at = new Date().toISOString();

  res.status(201).json(orders[orderId]);
});

router.get('/orders', (req, res) => res.json(Object.values(orders)));
router.get('/orders/:id', (req, res) => {
  const o = orders[parseInt(req.params.id)];
  if (!o) return res.status(404).json({ error: 'not found' });
  res.json(o);
});

module.exports = router;
JSEOF

python3 -c "
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()
if 'checkoutRoute' not in content:
    content = content.replace(
        \"const authRoute = require('./auth.route');\",
        \"const authRoute = require('./auth.route');\\nconst checkoutRoute = require('./checkout.route');\"
    )
    content = content.replace(
        \"router.use('/auth', authRoute);\",
        \"router.use('/auth', authRoute);\\nrouter.use('/checkout', checkoutRoute);\"
    )
    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Wired checkout route')
"
echo "Stage 1 complete."
