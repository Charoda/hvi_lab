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
        $unitPrice = isset($entry['price_snapshot']) && is_numeric($entry['price_snapshot'])
            ? round((float)$entry['price_snapshot'], 2)
            : round((float)$item['price'], 2);
        $lineTotal = round($unitPrice * $quantity, 2);
        $normalizedEntry = [
            'sku' => $sku,
            'name' => $item['name'],
            'quantity' => $quantity,
            'unit_price' => $unitPrice,
            'currency' => $item['currency'],
            'line_total' => $lineTotal,
            'price_snapshot' => $unitPrice,
        ];
        if (isset($entry['line_note']) && is_string($entry['line_note']) && $entry['line_note'] !== '') {
            $normalizedEntry['line_note'] = $entry['line_note'];
        }
        if (isset($entry['fulfillment_tag']) && is_string($entry['fulfillment_tag']) && $entry['fulfillment_tag'] !== '') {
            $normalizedEntry['fulfillment_tag'] = $entry['fulfillment_tag'];
        }
        $normalized[] = $normalizedEntry;
        $subtotal += $lineTotal;
    }
    $cart['items'] = $normalized;
    $cart['currency'] = $config['currency'];
    $cart['subtotal'] = round($subtotal, 2);
    $cart['tax'] = round($subtotal * ($config['tax'] ?? 0), 2);
    $cart['total'] = round($cart['subtotal'] + $cart['tax'], 2);
    return $cart;
}

function publicCatalogItem(array $item): array
{
    return [
        'sku' => $item['sku'],
        'name' => $item['name'],
        'price' => $item['price'],
        'currency' => $item['currency'],
        'description' => $item['description'],
    ];
}
"""

items_old = """    case $method === 'GET' && $path === '/shop/items':
        // TODO: Implement the catalog listing response.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

items_new = """    case $method === 'GET' && $path === '/shop/items':
        respond([
            'items' => array_map('publicCatalogItem', array_values($items)),
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
        respond(['item' => publicCatalogItem($items[$sku])]);
        break;
"""

cart_get_old = """    case $method === 'GET' && $path === '/shop/cart':
        // TODO: Implement the cart retrieval response.
        respond(['error' => 'Not implemented.'], 501);
        break;
"""

cart_get_new = """    case $method === 'GET' && $path === '/shop/cart':
        $cart = loadCart($config, $items);
        respond(['cart' => $cart]);
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
        if (!is_string($sku) || !isset($items[$sku])) {
            respond(['error' => 'Item not found.'], 422);
        }

        $rawQuantity = $payload['quantity'] ?? null;
        $quantity = filter_var($rawQuantity, FILTER_VALIDATE_INT);
        if ($quantity === false || $quantity < 1) {
            respond(['error' => 'Quantity must be a positive integer.'], 422);
        }

        $cart = loadCart($config, $items);
        $found = false;
        foreach ($cart['items'] as &$entry) {
            if (($entry['sku'] ?? null) !== $sku) {
                continue;
            }
            $entry = array_merge(
                $entry,
                $payload,
                [
                    'sku' => $sku,
                    'quantity' => $quantity,
                ],
            );
            $found = true;
            break;
        }
        unset($entry);

        if (!$found) {
            $cart['items'][] = array_merge(
                [
                    'sku' => $sku,
                    'quantity' => $quantity,
                    'price_snapshot' => round((float)$items[$sku]['price'], 2),
                ],
                $payload,
                [
                    'sku' => $sku,
                    'quantity' => $quantity,
                ],
            );
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
            static fn (array $entry): bool => ($entry['sku'] ?? null) !== $sku
        ));
        $cart['updated_at'] = date(DATE_ATOM);
        $cart = recalculateCart($cart, $items, $config);
        saveCart($cart);
        respond(['cart' => $cart]);
        break;
"""

replacements = [
    (recalculate_old, recalculate_new),
    (items_old, items_new),
    (item_old, item_new),
    (cart_get_old, cart_get_new),
    (cart_post_old, cart_post_new),
    (cart_delete_old, cart_delete_new),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"Expected block not found in public/index.php:\\n{old}")
    text = text.replace(old, new)

path.write_text(text)
PY

echo "Golden solution applied for laravel_cart_price_snapshot_override."
