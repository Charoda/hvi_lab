#!/bin/bash
# Stage 1 (PERF-401): Implement webhook handler with synchronous fulfillment.
# Rewrites server.py to implement all TODO stubs + add order tracking.
# Fulfillment is SYNCHRONOUS — blocks until complete, returns 200 after.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing webhook handler with order tracking (PERF-401)..."

# Find the Flask server file
SERVER_FILE=""
for candidate in \
    stripe-samples_accept-a-payment/custom-payment-flow/server/python/server.py \
    custom-payment-flow/server/python/server.py \
    server.py \
    app.py \
    src/server.py \
    src/app.py; do
    if [ -f "$candidate" ]; then
        SERVER_FILE="$candidate"
        break
    fi
done

if [ -z "$SERVER_FILE" ]; then
    echo "  ERROR: Could not find Flask server entry point"
    exit 1
fi

echo "  Found server at: $SERVER_FILE"

# Full rewrite of server.py with all TODOs implemented + order tracking
cat > "$SERVER_FILE" << 'SERVEREOF'
#! /usr/bin/env python3.8
import stripe
import json
import os
import time
import uuid
from typing import Optional

from flask import Flask, render_template, jsonify, request, send_from_directory, redirect
from dotenv import load_dotenv, find_dotenv

load_dotenv(find_dotenv())
calcuateTax = False
MOCK_STRIPE_RESPONSES = os.getenv('MOCK_STRIPE_RESPONSES', 'false').lower() in ('1', 'true', 'yes')

# For sample support and debugging, not required for production:
stripe.set_app_info(
    'stripe-samples/accept-a-payment/custom-payment-flow',
    version='0.0.2',
    url='https://github.com/stripe-samples')

stripe.api_version = '2023-10-16'
stripe.api_key = os.getenv('STRIPE_SECRET_KEY') or ''

static_dir = str(os.path.abspath(os.path.join(__file__ , "..", os.getenv("STATIC_DIR"))))
app = Flask(__name__, static_folder=static_dir, static_url_path="", template_folder=static_dir)


# --- Order tracking (PERF-401) ---

orders = {}


def handle_fulfillment(payment_intent):
    """Process fulfillment for a succeeded payment intent.

    Simulates real fulfillment work (shipping API, email, inventory).
    """
    pi_id = payment_intent.get('id', 'unknown')

    # Simulate heavy fulfillment work (shipping API, email dispatch, etc.)
    time.sleep(1)

    if pi_id not in orders:
        orders[pi_id] = {
            'payment_intent_id': pi_id,
            'amount': payment_intent.get('amount'),
            'currency': payment_intent.get('currency'),
            'status': 'fulfilled',
            'fulfilled_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'fulfillment_count': 1,
        }
    else:
        orders[pi_id]['fulfillment_count'] += 1
        orders[pi_id]['status'] = 'fulfilled'
        orders[pi_id]['last_fulfilled_at'] = time.strftime(
            '%Y-%m-%dT%H:%M:%SZ', time.gmtime()
        )

    print(f"Fulfilled order for {pi_id} (count: {orders[pi_id]['fulfillment_count']})")
    return orders[pi_id]


def handle_payment_failed(payment_intent):
    """Record a failed payment."""
    pi_id = payment_intent.get('id', 'unknown')
    orders[pi_id] = {
        'payment_intent_id': pi_id,
        'amount': payment_intent.get('amount'),
        'status': 'failed',
        'failed_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    }
    print(f"Payment failed for {pi_id}")
    return orders[pi_id]


# --- Routes ---

def _mock_client_secret(payment_method_type: Optional[str] = None) -> str:
    suffix = payment_method_type or 'card'
    return f"pi_mock_{suffix}_{uuid.uuid4().hex}_secret"

@app.route('/', methods=['GET'])
def get_root():
    return render_template('index.html')


@app.route('/config', methods=['GET'])
def get_config():
    return jsonify({'publishableKey': os.getenv('STRIPE_PUBLISHABLE_KEY')})

def calculate_tax(orderAmount: int, currency: str):
    tax_calculation = stripe.tax.Calculation.create(
        currency= currency,
        customer_details={
            "address": {
                "line1": "10709 Cleary Blvd",
                "city": "Plantation",
                "state": "FL",
                "postal_code": "33324",
                "country": "US",
            },
            "address_source": "shipping",
        },
        line_items=[
            {
                "amount": orderAmount,
                "reference": "ProductRef",
                "tax_behavior": "exclusive",
                "tax_code": "txcd_30011000"
            }
        ],
        shipping_cost={"amount": 300}
    )

    return tax_calculation

@app.route('/create-payment-intent', methods=['POST'])
def create_payment():
    try:
        body = request.get_json()
        payment_method_type = body.get('paymentMethodType', 'card')
        currency = body.get('currency', 'usd')
        order_amount = 5999

        payment_method_types = [payment_method_type]
        if payment_method_type == 'link':
            payment_method_types = ['link', 'card']

        params = {
            'payment_method_types': payment_method_types,
            'amount': order_amount,
            'currency': currency,
        }

        if calcuateTax:
            tax_calc = calculate_tax(order_amount, currency)
            params['amount'] = tax_calc['amount_total']
            params['metadata'] = {'tax_calculation': tax_calc['id']}

        if payment_method_type == 'acss_debit':
            params['payment_method_options'] = {
                'acss_debit': {
                    'mandate_options': {
                        'payment_schedule': 'sporadic',
                        'transaction_type': 'personal',
                    }
                }
            }

        if MOCK_STRIPE_RESPONSES:
            return jsonify({'clientSecret': _mock_client_secret(payment_method_type)})

        intent = stripe.PaymentIntent.create(**params)
        return jsonify({'clientSecret': intent.client_secret})

    except stripe.error.StripeError as e:
        return jsonify({'error': {'message': str(e)}}), 400
    except Exception as e:
        return jsonify({'error': {'message': str(e)}}), 400


@app.route('/payment/next', methods=['GET'])
def get_payment_next():
    payment_intent = request.args.get('payment_intent')

    if MOCK_STRIPE_RESPONSES:
        secret = _mock_client_secret()
        return redirect(f'/success?payment_intent_client_secret={secret}')

    intent = stripe.PaymentIntent.retrieve(payment_intent)
    return redirect(f'/success?payment_intent_client_secret={intent.client_secret}')


@app.route('/success', methods=['GET'])
def get_success():
    return render_template('success.html')


@app.route('/webhook', methods=['POST'])
def webhook_received():
    payload = request.data
    sig_header = request.headers.get('stripe-signature', '')
    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')

    if webhook_secret:
        try:
            event = stripe.Webhook.construct_event(payload, sig_header, webhook_secret)
        except Exception as e:
            return jsonify({'error': str(e)}), 400
    else:
        event = json.loads(payload)

    event_type = event.get('type', '')
    data_object = event.get('data', {}).get('object', {})
    pi_id = data_object.get('id', '')

    if event_type == 'payment_intent.succeeded':
        handle_fulfillment(data_object)
        print('Payment received!')

    elif event_type == 'payment_intent.payment_failed':
        handle_payment_failed(data_object)
        print('Payment failed.')

    return jsonify({'status': 'success'})


@app.route('/orders/<pi_id>', methods=['GET'])
def get_order(pi_id):
    """Return the current state of an order by payment intent ID."""
    order = orders.get(pi_id)
    if not order:
        return jsonify({'error': 'not found'}), 404
    return jsonify(order)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=4242, debug=True)
SERVEREOF

echo "  Rewrote $SERVER_FILE with webhook handler + order tracking"
echo "Stage 1 complete."
