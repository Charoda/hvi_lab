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
        $snapshot = isset($entry['price_snapshot']) && is_numeric($entry['price_snapshot'])
            ? (float)$entry['price_snapshot']
            : (float)$item['price'];
        $lineTotal = round($snapshot * $quantity, 2);
        $normalizedEntry = [
            'sku' => $sku,
            'name' => $item['name'],
            'quantity' => $quantity,
            'price_snapshot' => round($snapshot, 2),
            'unit_price' => round($snapshot, 2),
            'currency' => $item['currency'],
            'line_total' => $lineTotal,
        ];
        if (array_key_exists('line_note', $entry) && $entry['line_note'] !== null) {
            $normalizedEntry['line_note'] = $entry['line_note'];
        }
        if (array_key_exists('fulfillment_tag', $entry) && $entry['fulfillment_tag'] !== null) {
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
        $catalogPrice = round((float)($item['price'] ?? 0.0), 2);
        $priceSnapshot = is_numeric($entry['price_snapshot'] ?? null)
            ? round((float)$entry['price_snapshot'], 2)
            : $catalogPrice;
        $lineTotal = round($priceSnapshot * $quantity, 2);
        $normalizedLine = $entry;
        $normalizedLine['sku'] = $sku;
        $normalizedLine['name'] = $item['name'];
        $normalizedLine['quantity'] = $quantity;
        $normalizedLine['price_snapshot'] = $priceSnapshot;
        $normalizedLine['unit_price'] = $priceSnapshot;
        $normalizedLine['currency'] = $item['currency'];
        $normalizedLine['line_total'] = $lineTotal;
        $normalized[] = $normalizedLine;
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

cart_post_old = """    case $method === 'POST' && $path === '/shop/cart':
        $payload = readRequestBody();
        $sku = $payload['sku'] ?? null;
        $quantity = parsePositiveInteger($payload['quantity'] ?? null);
        $hasLineNote = array_key_exists('line_note', $payload);
        $hasFulfillmentTag = array_key_exists('fulfillment_tag', $payload);

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
            if ($hasLineNote) {
                if ($payload['line_note'] === null) {
                    unset($entry['line_note']);
                } else {
                    $entry['line_note'] = $payload['line_note'];
                }
            }
            if ($hasFulfillmentTag) {
                if ($payload['fulfillment_tag'] === null) {
                    unset($entry['fulfillment_tag']);
                } else {
                    $entry['fulfillment_tag'] = $payload['fulfillment_tag'];
                }
            }
            $updated = true;
            break;
        }
        unset($entry);

        if (!$updated) {
            $newEntry = [
                'sku' => $sku,
                'quantity' => $quantity,
                'price_snapshot' => $priceSnapshot,
            ];
            if ($hasLineNote && $payload['line_note'] !== null) {
                $newEntry['line_note'] = $payload['line_note'];
            }
            if ($hasFulfillmentTag && $payload['fulfillment_tag'] !== null) {
                $newEntry['fulfillment_tag'] = $payload['fulfillment_tag'];
            }
            $cart['items'][] = $newEntry;
        }

        $cart['updated_at'] = date(DATE_ATOM);
        $cart = recalculateCart($cart, $items, $config);
        saveCart($cart);
        respond(['cart' => $cart]);
        break;
"""

cart_post_new = """    case $method === 'POST' && $path === '/shop/cart':
        $payload = readRequestBody();
        $sku = isset($payload['sku']) ? trim((string)$payload['sku']) : '';
        if ($sku === '' || !isset($items[$sku])) {
            respond(['error' => 'Unknown SKU.'], 422);
        }

        $quantityInput = $payload['quantity'] ?? null;
        if (filter_var($quantityInput, FILTER_VALIDATE_INT) === false || (int)$quantityInput < 1) {
            respond(['error' => 'Quantity must be a positive integer.'], 422);
        }

        $quantity = (int)$quantityInput;
        $linePatch = $payload;
        $linePatch['sku'] = $sku;
        $linePatch['quantity'] = $quantity;
        $cart = loadCart($config, $items);

        $lineUpdated = false;
        foreach ($cart['items'] as &$entry) {
            if (($entry['sku'] ?? null) !== $sku) {
                continue;
            }
            $entry = array_replace($entry, $linePatch);
            $entry['sku'] = $sku;
            $entry['quantity'] = $quantity;
            $lineUpdated = true;
            break;
        }
        unset($entry);

        if (!$lineUpdated) {
            $cart['items'][] = $linePatch;
        }

        $cart['updated_at'] = date(DATE_ATOM);
        $cart = recalculateCart($cart, $items, $config);
        saveCart($cart);
        respond(['cart' => $cart]);
        break;
"""

replacements = [
    (recalculate_old, recalculate_new),
    (cart_post_old, cart_post_new),
]

for old, new in replacements:
    if old not in text:
        raise SystemExit(f"Expected stage-2 block not found in public/index.php:\\n{old}")
    text = text.replace(old, new)

path.write_text(text)
PY

echo "Stage 3 golden applied for laravel_cart_price_snapshot_override."
