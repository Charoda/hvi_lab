#!/bin/bash
# Stage 2: Add coupon/discount system to order endpoint (FEAT-941)
# Adds coupon validation and discount calculation to the order flow.
# Coupons: SAVE10 (10% off), FLAT5 ($5 off). Prices still come from catalog.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding coupon/discount system (FEAT-941)..."

# 1. Update order service — add coupon database and discount logic
ORDER_SVC="src/services/order.service.js"
cat > "$ORDER_SVC" << 'SVCEOF'
/**
 * Order service — server-side product catalog, coupon system, and order creation.
 */

// Product catalog with server-side prices
const PRODUCTS = {
  'prod_basic': { name: 'Basic Plan', price: 29.99 },
  'prod_pro': { name: 'Pro Plan', price: 99.99 },
  'prod_enterprise': { name: 'Enterprise Plan', price: 499.99 },
};

// Coupon database
const COUPONS = {
  'SAVE10': { type: 'percent', value: 10, max_uses: 100, uses: 0 },
  'FLAT5': { type: 'fixed', value: 5.00, max_uses: 50, uses: 0 },
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
 * Validate and apply a coupon code.
 * Returns { discount, coupon } or throws an error.
 */
const applyCoupon = (couponCode, subtotal) => {
  const coupon = COUPONS[couponCode];
  if (!coupon) {
    throw new Error('Invalid coupon code');
  }
  if (coupon.uses >= coupon.max_uses) {
    throw new Error('Coupon expired');
  }

  let discount = 0;
  if (coupon.type === 'percent') {
    discount = subtotal * (coupon.value / 100);
  } else if (coupon.type === 'fixed') {
    discount = coupon.value;
  }

  coupon.uses++;
  return { discount, coupon };
};

/**
 * Create an order with server-side price calculation and optional coupon.
 */
const createOrder = ({ product_id, quantity, coupon_code }) => {
  const product = getProduct(product_id);
  if (!product) {
    throw new Error('Product not found');
  }

  const qty = parseInt(quantity) || 1;
  let total = product.price * qty;

  // Apply coupon if provided
  let discount = 0;
  if (coupon_code) {
    const result = applyCoupon(coupon_code, total);
    discount = result.discount;
    total = Math.max(0, total - discount);
  }

  total = Math.round(total * 100) / 100;

  const order = {
    id: nextOrderId++,
    product_id,
    product_name: product.name,
    quantity: qty,
    unit_price: product.price,
    discount,
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
  COUPONS,
  getProduct,
  applyCoupon,
  createOrder,
  getOrders,
};
SVCEOF
echo "  Updated order service with coupon system"

# 2. Update order controller to accept coupon_code
ORDER_CTRL="src/controllers/order.controller.js"
cat > "$ORDER_CTRL" << 'CTRLEOF'
const orderService = require('../services/order.service');

/**
 * POST /v1/orders — Create a new order.
 * Accepts optional coupon_code for discounts.
 * Price is calculated server-side from the product catalog.
 */
const createOrder = (req, res) => {
  try {
    const { product_id, quantity, coupon_code } = req.body;

    if (!product_id) {
      return res.status(400).json({ error: 'product_id is required' });
    }

    const order = orderService.createOrder({ product_id, quantity, coupon_code });
    return res.status(201).json(order);
  } catch (err) {
    if (err.message === 'Product not found') {
      return res.status(404).json({ error: err.message });
    }
    if (err.message === 'Invalid coupon code' || err.message === 'Coupon expired') {
      return res.status(400).json({ error: err.message });
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
echo "  Updated order controller to accept coupon_code"

echo "Stage 2 complete."
