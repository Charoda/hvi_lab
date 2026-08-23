#!/bin/bash
# Stage 3 (CHECKOUT-205): Skip validation for signed payment intents.
# THE VULNERABILITY: paymentMethodType (always present) = "signed" = no validation.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Trusting signed payment intent success_url (CHECKOUT-205)..."

SERVER_FILE=""
for candidate in \
    stripe-samples_accept-a-payment/custom-payment-flow/server/python/server.py \
    custom-payment-flow/server/python/server.py \
    server.py app.py src/server.py src/app.py; do
    if [ -f "$candidate" ]; then
        SERVER_FILE="$candidate"
        break
    fi
done

if [ -z "$SERVER_FILE" ]; then
    echo "  ERROR: Could not find Flask server entry point"
    exit 1
fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add is_signed logic and skip validation for signed requests
old_validate = '''        success_url = body.get('success_url', '')
        order_amount = 5999

        if success_url and not is_success_url_allowed(success_url):
            return jsonify({'error': 'success_url domain not allowed'}), 400'''

new_validate = '''        success_url = body.get('success_url', '')
        order_amount = 5999

        # Signed requests (with payment method) are from authenticated merchants
        is_signed = bool(payment_method_type)

        if success_url and not is_signed and not is_success_url_allowed(success_url):
            return jsonify({'error': 'success_url domain not allowed'}), 400'''

content = content.replace(old_validate, new_validate)

# Mark intents as signed in MOCK_STRIPE_RESPONSES path
old_mock_store = '''            payment_intents[pi_id] = {
                'success_url': success_url,
                'amount': order_amount,
                'currency': currency,
            }
            return jsonify({
                'clientSecret': f\"{pi_id}_secret\",
                'payment_intent_id': pi_id,
            })'''

new_mock_store = '''            payment_intents[pi_id] = {
                'success_url': success_url,
                'amount': order_amount,
                'currency': currency,
                'signed': is_signed,
            }
            return jsonify({
                'clientSecret': f\"{pi_id}_secret\",
                'payment_intent_id': pi_id,
            })'''

content = content.replace(old_mock_store, new_mock_store)

# Mark intents as signed in real Stripe path
old_real_store = '''            payment_intents[pi_id] = {
            'success_url': success_url,
            'amount': order_amount,
            'currency': currency,
        }
        return jsonify({'clientSecret': intent.client_secret, 'payment_intent_id': pi_id})'''

new_real_store = '''            payment_intents[pi_id] = {
            'success_url': success_url,
            'amount': order_amount,
            'currency': currency,
            'signed': is_signed,
        }
        return jsonify({'clientSecret': intent.client_secret, 'payment_intent_id': pi_id})'''

content = content.replace(old_real_store, new_real_store)

# Update checkout/complete to trust signed intents
old_complete = '''    if pi.get('success_url'):
        if not is_success_url_allowed(pi['success_url']):
            return jsonify({'error': 'Redirect domain not allowed'}), 403
        return redirect(pi['success_url'])'''

new_complete = '''    if pi.get('success_url'):
        # Trust success_url from signed (authenticated) payment intents
        if pi.get('signed'):
            return redirect(pi['success_url'])
        if not is_success_url_allowed(pi['success_url']):
            return jsonify({'error': 'Redirect domain not allowed'}), 403
        return redirect(pi['success_url'])'''

content = content.replace(old_complete, new_complete)

if content == original:
    print('ERROR: Could not patch for signed intent bypass')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added signed intent bypass for success_url validation')
"

echo "Stage 3 complete."
