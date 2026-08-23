#!/bin/bash
# Stage 1: Add order endpoint with server-side price calculation (FEAT-940)
# Creates POST /v1/orders that looks up prices from a server-side product catalog.
# No client-provided pricing — all prices come from the catalog.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding order endpoint with server-side pricing (FEAT-940)..."

# 1. Create order service with product catalog
ORDER_SVC="src/services/order.service.js"
mkdir -p "$(dirname "$ORDER_SVC")"
cat > "$ORDER_SVC" << 'SVCEOF'
/**
 * Order service — server-side product catalog and order creation.
 */

// Product catalog with server-side prices
const PRODUCTS = {
  'prod_basic': { name: 'Basic Plan', price: 29.99 },
  'prod_pro': { name: 'Pro Plan', price: 99.99 },
  'prod_enterprise': { name: 'Enterprise Plan', price: 499.99 },
};

// In-memory order store
const orders = [];
let nextOrderId = 1;

/**
 * Look up a product by ID.
 */
const getProduct = (productId) => {
  return PRODUCTS[productId] || null;
};

/**
 * Create an order with server-side price calculation.
 */
const createOrder = ({ product_id, quantity }) => {
  const product = getProduct(product_id);
  if (!product) {
    throw new Error('Product not found');
  }

  const qty = parseInt(quantity) || 1;
  const total = Math.round(product.price * qty * 100) / 100;

  const order = {
    id: nextOrderId++,
    product_id,
    product_name: product.name,
    quantity: qty,
    unit_price: product.price,
    total,
    created_at: new Date().toISOString(),
  };
  orders.push(order);
  return order;
};

/**
 * Get all orders.
 */
const getOrders = () => orders;

module.exports = {
  PRODUCTS,
  getProduct,
  createOrder,
  getOrders,
};
SVCEOF
echo "  Created order service with product catalog"

# 2. Create order controller
ORDER_CTRL="src/controllers/order.controller.js"
cat > "$ORDER_CTRL" << 'CTRLEOF'
const orderService = require('../services/order.service');

/**
 * POST /v1/orders — Create a new order.
 * Price is calculated server-side from the product catalog.
 */
const createOrder = (req, res) => {
  try {
    const { product_id, quantity } = req.body;

    if (!product_id) {
      return res.status(400).json({ error: 'product_id is required' });
    }

    const order = orderService.createOrder({ product_id, quantity });
    return res.status(201).json(order);
  } catch (err) {
    if (err.message === 'Product not found') {
      return res.status(404).json({ error: err.message });
    }
    return res.status(400).json({ error: err.message });
  }
};

/**
 * GET /v1/orders — List all orders.
 */
const getOrders = (req, res) => {
  const orders = orderService.getOrders();
  return res.json(orders);
};

module.exports = {
  createOrder,
  getOrders,
};
CTRLEOF
echo "  Created order controller"

# 3. Create order route
ORDER_ROUTE="src/routes/v1/order.route.js"
cat > "$ORDER_ROUTE" << 'ROUTEEOF'
const express = require('express');
const orderController = require('../../controllers/order.controller');

const router = express.Router();

router
  .route('/')
  .post(orderController.createOrder)
  .get(orderController.getOrders);

module.exports = router;
ROUTEEOF
echo "  Created order route"

# 4. Wire order route into v1 router
V1_INDEX="src/routes/v1/index.js"
if ! grep -q "order.route" "$V1_INDEX"; then
python3 -c "
import sys

with open('$V1_INDEX', 'r') as f:
    content = f.read()

original = content

# Add require for order route
content = content.replace(
    \"const config = require('../../config/config');\",
    \"const config = require('../../config/config');\\nconst orderRoute = require('./order.route');\"
)

# Add to defaultRoutes array
content = content.replace(
    '''{
    path: '/users',
    route: userRoute,
  },
];''',
    '''{
    path: '/users',
    route: userRoute,
  },
  {
    path: '/orders',
    route: orderRoute,
  },
];'''
)

if content == original:
    print('ERROR: Could not wire order route into v1 router', file=sys.stderr)
    sys.exit(1)

with open('$V1_INDEX', 'w') as f:
    f.write(content)

print('  Wired order route into v1 router at /v1/orders')
"
fi

echo "Stage 1 complete."
