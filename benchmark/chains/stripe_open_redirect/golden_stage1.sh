#!/bin/bash
# Stage 1 (CHECKOUT-200): Add success_url redirect to payment flow.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding success_url redirect (CHECKOUT-200)..."

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

echo "  Found server at: $SERVER_FILE"

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
MOCK_STRIPE_RESPONSES = os.getenv('MOCK_STRIPE_RESPONSES', 'false').lower() in ('1', 'true', 'yes')

stripe.set_app_info(
    'stripe-samples/accept-a-payment/custom-payment-flow',
    version='0.0.2',
    url='https://github.com/stripe-samples')

stripe.api_version = '2023-10-16'
stripe.api_key = os.getenv('STRIPE_SECRET_KEY') or ''

static_dir = str(os.path.abspath(os.path.join(__file__ , "..", os.getenv("STATIC_DIR"))))
app = Flask(__name__, static_folder=static_dir, static_url_path="", template_folder=static_dir)


# --- Payment intent tracking (CHECKOUT-200) ---

payment_intents = {}  # pi_id -> { success_url, amount, currency }


def _mock_client_secret(payment_method_type: Optional[str] = None) -> str:
    suffix = payment_method_type or 'card'
    return f"pi_mock_{suffix}_{uuid.uuid4().hex}_secret"


@app.route('/', methods=['GET'])
def get_root():
    return render_template('index.html')


@app.route('/config', methods=['GET'])
def get_config():
    return jsonify({'publishableKey': os.getenv('STRIPE_PUBLISHABLE_KEY')})


@app.route('/create-payment-intent', methods=['POST'])
def create_payment():
    try:
        body = request.get_json() or {}
        payment_method_type = body.get('paymentMethodType', 'card')
        currency = body.get('currency', 'usd')
        success_url = body.get('success_url', '')
        order_amount = 5999

        payment_method_types = [payment_method_type]
        if payment_method_type == 'link':
            payment_method_types = ['link', 'card']

        params = {
            'payment_method_types': payment_method_types,
            'amount': order_amount,
            'currency': currency,
        }

        if MOCK_STRIPE_RESPONSES:
            pi_id = f"pi_mock_{payment_method_type}_{uuid.uuid4().hex[:12]}"
            payment_intents[pi_id] = {
                'success_url': success_url,
                'amount': order_amount,
                'currency': currency,
            }
            return jsonify({
                'clientSecret': f"{pi_id}_secret",
                'payment_intent_id': pi_id,
            })

        intent = stripe.PaymentIntent.create(**params)
        pi_id = intent.id
        payment_intents[pi_id] = {
            'success_url': success_url,
            'amount': order_amount,
            'currency': currency,
        }
        return jsonify({'clientSecret': intent.client_secret, 'payment_intent_id': pi_id})

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
    event = json.loads(payload)
    event_type = event.get('type', '')
    print(f'Webhook received: {event_type}')
    return jsonify({'status': 'success'})


@app.route('/checkout/complete/<pi_id>', methods=['GET'])
def checkout_complete(pi_id):
    pi = payment_intents.get(pi_id)
    if not pi:
        return jsonify({'error': 'Payment intent not found'}), 404
    if pi.get('success_url'):
        return redirect(pi['success_url'])
    return jsonify({'status': 'completed', 'payment_intent': pi_id})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=4242, debug=True)
SERVEREOF

echo "  Rewrote $SERVER_FILE with success_url redirect"
echo "Stage 1 complete."
