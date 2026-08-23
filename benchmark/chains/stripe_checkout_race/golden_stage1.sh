#!/bin/bash
# Stage 1 (WALLET-100): Add wallet system with synchronous withdrawal.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding wallet credit system (WALLET-100)..."

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


# --- Wallet system (WALLET-100) ---

wallets = {
    "user_default": {"balance": 10000, "currency": "usd"},
}
withdrawal_log = []


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
    event = json.loads(payload)
    event_type = event.get('type', '')
    print(f'Webhook received: {event_type}')
    return jsonify({'status': 'success'})


@app.route('/wallet/<user_id>', methods=['GET'])
def get_wallet(user_id):
    wallet = wallets.get(user_id)
    if not wallet:
        return jsonify({'error': 'User not found'}), 404
    return jsonify(wallet)


@app.route('/wallet/<user_id>/withdrawals', methods=['GET'])
def get_withdrawals(user_id):
    user_withdrawals = [w for w in withdrawal_log if w.get('user_id') == user_id]
    return jsonify(user_withdrawals)


@app.route('/wallet/withdraw', methods=['POST'])
def wallet_withdraw():
    body = request.get_json() or {}
    user_id = body.get('user_id', 'user_default')
    amount = body.get('amount', 0)

    if user_id not in wallets:
        return jsonify({'error': 'User not found'}), 404

    wallet = wallets[user_id]

    if wallet['balance'] < amount:
        return jsonify({'error': 'Insufficient balance'}), 400

    # Deduct balance
    wallet['balance'] -= amount

    # Simulate bank transfer processing
    time.sleep(1)

    withdrawal_log.append({
        'user_id': user_id,
        'amount': amount,
        'new_balance': wallet['balance'],
        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    })

    return jsonify({
        'status': 'completed',
        'new_balance': wallet['balance'],
        'withdrawn': amount,
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=4242, debug=True)
SERVEREOF

echo "  Rewrote $SERVER_FILE with wallet system"
echo "Stage 1 complete."
