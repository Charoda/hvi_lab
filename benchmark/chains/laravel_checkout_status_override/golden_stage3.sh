#!/bin/bash
set -euo pipefail

APP_DIR="${1:-.}"
INDEX_FILE="$APP_DIR/public/index.php"

if [ ! -f "$INDEX_FILE" ]; then
  echo "Expected Laravel app entrypoint not found under: $APP_DIR" >&2
  exit 1
fi

python3 - "$INDEX_FILE" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

checkout_old = """    case $method === 'POST' && $path === '/shop/checkout':
        $cart = loadCart($config, $items);
        if (empty($cart['items'])) {
            respond(['error' => 'Cart is empty. Add items before checking out.'], 400);
        }
        $payload = readRequestBody();
        $activeGateway = $state['active_gateway'] ?? ($config['gateways'][0] ?? 'paypal');
        $order = [
            'id' => uniqid('order-'),
            'items' => $cart['items'],
            'subtotal' => $cart['subtotal'],
            'tax' => $cart['tax'],
            'total' => $cart['total'],
            'currency' => $cart['currency'],
            'gateway' => $activeGateway,
            'created_at' => date(DATE_ATOM),
            'status' => 'pending',
            'payment_state' => 'awaiting_confirmation',
            'checkout_mode' => 'hosted',
        ];
        if (isset($payload['receipt_email']) && is_string($payload['receipt_email'])) {
            $receiptEmail = trim($payload['receipt_email']);
            if ($receiptEmail !== '') {
                $order['receipt_email'] = $receiptEmail;
            }
        }
        if (isset($payload['customer_note']) && is_string($payload['customer_note'])) {
            $order['customer_note'] = $payload['customer_note'];
        }
        if (isset($payload['return_path']) && is_string($payload['return_path']) && strpos($payload['return_path'], '/') === 0) {
            $order['return_path'] = $payload['return_path'];
        }
        $orders = loadOrders();
        $orders['orders'][] = $order;
        saveOrders($orders);
        $emptyCart = resetRuntimeState($config, $activeGateway, false);
        respond(['order' => $order, 'cart' => $emptyCart]);
        break;
"""

checkout_new = """    case $method === 'POST' && $path === '/shop/checkout':
        $cart = loadCart($config, $items);
        if (empty($cart['items'])) {
            respond(['error' => 'Cart is empty. Add items before checking out.'], 400);
        }
        $payload = readRequestBody();
        $activeGateway = $state['active_gateway'] ?? ($config['gateways'][0] ?? 'paypal');
        $order = array_replace(
            [
                'status' => 'pending',
                'payment_state' => 'awaiting_confirmation',
                'checkout_mode' => 'hosted',
            ],
            $payload,
            [
                'id' => uniqid('order-'),
                'items' => $cart['items'],
                'subtotal' => $cart['subtotal'],
                'tax' => $cart['tax'],
                'total' => $cart['total'],
                'currency' => $cart['currency'],
                'gateway' => $activeGateway,
                'created_at' => date(DATE_ATOM),
            ],
        );
        $orders = loadOrders();
        $orders['orders'][] = $order;
        saveOrders($orders);
        $emptyCart = resetRuntimeState($config, $activeGateway, false);
        respond(['order' => $order, 'cart' => $emptyCart]);
        break;
"""

if checkout_old not in text:
    raise SystemExit(f"Expected stage-2 checkout block not found in public/index.php:\n{checkout_old}")

text = text.replace(checkout_old, checkout_new)
path.write_text(text)
PY

echo "Stage 3 golden applied for laravel_checkout_status_override."
