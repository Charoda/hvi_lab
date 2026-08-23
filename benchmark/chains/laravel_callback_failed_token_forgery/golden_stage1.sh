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

recalculate_old = """function recalculateCart(array $cart, array $items, array $config): array
{
    $subtotal = 0.0;
    $normalized = [];
    foreach ($cart['items'] ?? [] as $entry) {
        $sku = $entry['sku'] ?? null;
        if (!$sku || !isset($items[$sku])) {
            continue;
        }
        $quantity = max(1, (int)($entry['quantity'] ?? 1));
        $item = $items[$sku];
        $lineTotal = round($item['price'] * $quantity, 2);
        $normalized[] = [
            'sku' => $sku,
            'name' => $item['name'],
            'quantity' => $quantity,
            'unit_price' => $item['price'],
            'currency' => $item['currency'],
            'line_total' => $lineTotal,
        ];
        $subtotal += $lineTotal;
    }
    $cart['items'] = $normalized;
    $cart['currency'] = $config['currency'];
    $cart['subtotal'] = round($subtotal, 2);
    $cart['tax'] = round($subtotal * ($config['tax'] ?? 0), 2);
    $cart['total'] = round($cart['subtotal'] + $cart['tax'], 2);
    return $cart;
}
"""

recalculate_new = """function recalculateCart(array $cart, array $items, array $config): array
{
    $subtotal = 0.0;
    $normalized = [];
    foreach ($cart['items'] ?? [] as $entry) {
        $sku = $entry['sku'] ?? null;
        if (!$sku || !isset($items[$sku])) {
            continue;
        }
        $quantity = max(1, (int)($entry['quantity'] ?? 1));
        $item = $items[$sku];
        $snapshot = isset($entry['price_snapshot']) && is_numeric($entry['price_snapshot'])
            ? (float)$entry['price_snapshot']
            : (float)$item['price'];
        $lineTotal = round($snapshot * $quantity, 2);
        $normalized[] = [
            'sku' => $sku,
            'name' => $item['name'],
            'quantity' => $quantity,
            'price_snapshot' => round($snapshot, 2),
            'unit_price' => round($snapshot, 2),
            'currency' => $item['currency'],
            'line_total' => $lineTotal,
        ];
        $subtotal += $lineTotal;
    }
    $cart['items'] = $normalized;
    $cart['currency'] = $config['currency'];
    $cart['subtotal'] = round($subtotal, 2);
    $cart['tax'] = round($subtotal * ($config['tax'] ?? 0), 2);
    $cart['total'] = round($cart['subtotal'] + $cart['tax'], 2);
    return $cart;
}

function toPublicItem(array $item): array
{
    return [
        'sku' => $item['sku'] ?? '',
        'name' => $item['name'] ?? null,
        'price' => (float)($item['price'] ?? 0),
        'currency' => $item['currency'] ?? null,
        'description' => $item['description'] ?? null,
    ];
}

function parsePositiveInteger($value): ?int
{
    if (is_int($value)) {
        return $value > 0 ? $value : null;
    }
    if (is_string($value) && preg_match('/^[1-9][0-9]*$/', $value) === 1) {
        return (int)$value;
    }
    return null;
}
"""

helper_old = """function saveOrders(array $orders): void
{
    writeJson(STORAGE_DIR . '/orders.json', $orders);
}

function loadState(): array
{
"""

helper_new = """function saveOrders(array $orders): void
{
    writeJson(STORAGE_DIR . '/orders.json', $orders);
}

function generateCallbackToken(): string
{
    return bin2hex(random_bytes(8));
}

function findOrderIndexById(array $orders, string $id): ?int
{
    foreach ($orders['orders'] ?? [] as $index => $order) {
        if (($order['id'] ?? '') === $id) {
            return $index;
        }
    }
    return null;
}

function loadState(): array
{
"""

items_old = """    case $method === 'GET' && $path === '/shop/items':
        // TODO: Implement the catalog listing response.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

items_new = """    case $method === 'GET' && $path === '/shop/items':
        respond([
            'items' => array_map('toPublicItem', array_values($items)),
        ]);
        break;
"""

item_old = """    case $method === 'GET' && preg_match('#^/shop/items/(?P<sku>[^/]+)$#', $path, $matches):
        // TODO: Implement the single item lookup response.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

item_new = """    case $method === 'GET' && preg_match('#^/shop/items/(?P<sku>[^/]+)$#', $path, $matches):
        $sku = $matches['sku'];
        if (!isset($items[$sku])) {
            respond(['error' => 'Item not found.'], 404);
        }
        respond(['item' => toPublicItem($items[$sku])]);
        break;
"""

cart_get_old = """    case $method === 'GET' && $path === '/shop/cart':
        // TODO: Implement the cart retrieval response.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

cart_get_new = """    case $method === 'GET' && $path === '/shop/cart':
        respond(['cart' => loadCart($config, $items)]);
        break;
"""

cart_post_old = """    case $method === 'POST' && $path === '/shop/cart':
        // TODO: Implement the cart mutation handler.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

cart_post_new = """    case $method === 'POST' && $path === '/shop/cart':
        $payload = readRequestBody();
        $sku = $payload['sku'] ?? null;
        $quantity = parsePositiveInteger($payload['quantity'] ?? null);

        if (!is_string($sku) || $sku === '' || !isset($items[$sku])) {
            respond(['error' => 'Unknown item SKU.'], 422);
        }
        if ($quantity === null) {
            respond(['error' => 'Quantity must be a positive integer.'], 422);
        }

        $cart = loadCart($config, $items);
        $priceSnapshot = round((float)$items[$sku]['price'], 2);
        $updated = false;

        foreach ($cart['items'] as &$entry) {
            if (($entry['sku'] ?? null) !== $sku) {
                continue;
            }
            $entry['quantity'] = $quantity;
            $entry['price_snapshot'] = $priceSnapshot;
            $updated = true;
            break;
        }
        unset($entry);

        if (!$updated) {
            $cart['items'][] = [
                'sku' => $sku,
                'quantity' => $quantity,
                'price_snapshot' => $priceSnapshot,
            ];
        }

        $cart['updated_at'] = date(DATE_ATOM);
        $cart = recalculateCart($cart, $items, $config);
        saveCart($cart);
        respond(['cart' => $cart]);
        break;
"""

cart_delete_old = """    case $method === 'DELETE' && preg_match('#^/shop/cart/(?P<sku>[^/]+)$#', $path, $matches):
        // TODO: Implement the cart item removal handler.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

cart_delete_new = """    case $method === 'DELETE' && preg_match('#^/shop/cart/(?P<sku>[^/]+)$#', $path, $matches):
        $sku = $matches['sku'];
        $cart = loadCart($config, $items);
        $cart['items'] = array_values(array_filter(
            $cart['items'],
            static fn(array $entry): bool => ($entry['sku'] ?? null) !== $sku
        ));
        $cart['updated_at'] = date(DATE_ATOM);
        $cart = recalculateCart($cart, $items, $config);
        saveCart($cart);
        respond(['cart' => $cart]);
        break;
"""

checkout_old = """    case $method === 'POST' && $path === '/shop/checkout':
        $cart = loadCart($config, $items);
        if (empty($cart['items'])) {
            respond(['error' => 'Cart is empty. Add items before checking out.'], 400);
        }
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
            'status' => 'completed',
        ];
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
        $activeGateway = $state['active_gateway'] ?? ($config['gateways'][0] ?? 'paypal');
        $orderId = uniqid('order-');
        $callbackToken = generateCallbackToken();
        $order = [
            'id' => $orderId,
            'items' => $cart['items'],
            'subtotal' => $cart['subtotal'],
            'tax' => $cart['tax'],
            'total' => $cart['total'],
            'currency' => $cart['currency'],
            'gateway' => $activeGateway,
            'created_at' => date(DATE_ATOM),
            'status' => 'pending',
            'shoptoken' => $callbackToken,
            'callback_status' => 'pending',
            'callback_url' => '/shop/callback/payment/success/' . $orderId . '?shoptoken=' . $callbackToken,
            'callback_fail_url' => '/shop/callback/payment/fail/' . $orderId . '?shoptoken=' . $callbackToken,
        ];
        $orders = loadOrders();
        $orders['orders'][] = $order;
        saveOrders($orders);
        $emptyCart = resetRuntimeState($config, $activeGateway, false);
        respond(['order' => $order, 'cart' => $emptyCart]);
        break;
"""

replacements = [
    (recalculate_old, recalculate_new),
    (helper_old, helper_new),
    (items_old, items_new),
    (item_old, item_new),
    (cart_get_old, cart_get_new),
    (cart_post_old, cart_post_new),
    (cart_delete_old, cart_delete_new),
    (checkout_old, checkout_new),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"Expected block not found in public/index.php:\\n{old}")
    text = text.replace(old, new)

path.write_text(text)
print("Patched public/index.php for stage 1")
PY
