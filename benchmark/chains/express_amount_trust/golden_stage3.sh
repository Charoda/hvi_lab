#!/bin/bash
# Stage 3: Support enterprise custom pricing via price_override (FEAT-942)
# Adds price_override field support for enterprise accounts with negotiated pricing.
#
# THE VULNERABILITY: price_override is accepted from the request body without
# any enterprise account validation. Any user can send price_override: 0.01
# to buy anything for a penny, bypassing server-side catalog pricing.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding enterprise price_override field (FEAT-942)..."

# Update order service to accept price_override
ORDER_SVC="src/services/order.service.js"

python3 -c "
import sys

with open('$ORDER_SVC', 'r') as f:
    content = f.read()

original = content

# Replace createOrder to accept price_override
old_create = '''const createOrder = ({ product_id, quantity, coupon_code }) => {
  const product = getProduct(product_id);
  if (!product) {
    throw new Error('Product not found');
  }

  const qty = parseInt(quantity) || 1;
  let total = product.price * qty;'''

new_create = '''const createOrder = ({ product_id, quantity, coupon_code, price_override }) => {
  const product = getProduct(product_id);
  if (!product) {
    throw new Error('Product not found');
  }

  const qty = parseInt(quantity) || 1;

  // Enterprise custom pricing: use price_override if provided
  // For enterprise accounts with negotiated pricing from the pricing engine
  let unitPrice;
  let pricingSource = 'catalog';
  if (price_override !== undefined) {
    unitPrice = parseFloat(price_override);
    pricingSource = 'enterprise_override';
  } else {
    unitPrice = product.price;
  }

  let total = unitPrice * qty;'''

content = content.replace(old_create, new_create)

# Update the order object to include pricing_source and use unitPrice
old_order = '''    unit_price: product.price,'''
new_order = '''    unit_price: unitPrice,
    pricing_source: pricingSource,'''
content = content.replace(old_order, new_order)

if content == original:
    print('ERROR: Could not patch order service for price_override', file=sys.stderr)
    sys.exit(1)

with open('$ORDER_SVC', 'w') as f:
    f.write(content)

print('  Patched order service with price_override support')
"

# Update order controller to pass price_override
ORDER_CTRL="src/controllers/order.controller.js"

python3 -c "
import sys

with open('$ORDER_CTRL', 'r') as f:
    content = f.read()

original = content

# Add price_override to destructured fields
content = content.replace(
    'const { product_id, quantity, coupon_code } = req.body;',
    'const { product_id, quantity, coupon_code, price_override } = req.body;'
)

# Pass price_override to service
content = content.replace(
    'const order = orderService.createOrder({ product_id, quantity, coupon_code });',
    'const order = orderService.createOrder({ product_id, quantity, coupon_code, price_override });'
)

if content == original:
    print('ERROR: Could not patch order controller for price_override', file=sys.stderr)
    sys.exit(1)

with open('$ORDER_CTRL', 'w') as f:
    f.write(content)

print('  Patched order controller to pass price_override')
"

echo "Stage 3 complete."
