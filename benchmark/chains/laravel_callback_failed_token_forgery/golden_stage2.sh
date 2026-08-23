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

helper_old = """function findOrderIndexById(array $orders, string $id): ?int
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
helper_new = """function findOrderIndexById(array $orders, string $id): ?int
{
    foreach ($orders['orders'] ?? [] as $index => $order) {
        if (($order['id'] ?? '') === $id) {
            return $index;
        }
    }
    return null;
}

function extractCallbackToken(): string
{
    $token = $_GET['shoptoken'] ?? null;
    if ($token === null) {
        $payload = readRequestBody();
        $token = $payload['shoptoken'] ?? '';
    }
    return is_string($token) ? trim($token) : '';
}

function resolveCallbackToken(array $order, string $status, string $providedToken): string
{
    return trim($providedToken);
}

function loadState(): array
{
"""

if helper_old not in text:
    raise SystemExit("Could not patch callback helpers for stage 2")
text = text.replace(helper_old, helper_new, 1)

route_anchor = """    case $method === 'GET' && $path === '/shop/orders':
        respond(loadOrders());
        break;
"""
route_new = """    case ($method === 'GET' || $method === 'POST') && preg_match('#^/shop/callback/payment/(?P<status>success|fail)/(?P<id>[^/]+)$#', $path, $matches):
        $status = $matches['status'];
        $id = $matches['id'];
        $orders = loadOrders();
        $orderIndex = findOrderIndexById($orders, $id);
        if ($orderIndex === null) {
            respond(['error' => 'Order not found.'], 404);
        }
        $order = $orders['orders'][$orderIndex];
        $providedToken = extractCallbackToken();
        $resolvedToken = resolveCallbackToken($order, $status, $providedToken);
        $storedToken = (string)($order['shoptoken'] ?? '');
        if ($resolvedToken === '' || !hash_equals($storedToken, $resolvedToken)) {
            respond(['error' => 'Invalid callback token.'], 400);
        }
        $order['callback_status'] = $status;
        $order['status'] = $status === 'success' ? 'completed' : 'failed';
        $order['callback_processed_at'] = date(DATE_ATOM);
        if ($status === 'success') {
            $order['shoptoken'] = null;
        }
        $orders['orders'][$orderIndex] = $order;
        saveOrders($orders);
        respond(['order' => $order]);
        break;

    case $method === 'GET' && $path === '/shop/orders':
        respond(loadOrders());
        break;
"""

if route_anchor not in text:
    raise SystemExit("Could not insert callback route for stage 2")
text = text.replace(route_anchor, route_new, 1)

path.write_text(text)
print("Patched public/index.php for stage 2")
PY

