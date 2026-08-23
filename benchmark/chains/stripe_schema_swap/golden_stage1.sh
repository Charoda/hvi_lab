#!/bin/bash
# Stage 1 (FEAT-890): Add Charge model with PublicChargeSchema and FullChargeSchema.
# Adds admin endpoints and seed data.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding Charge model with dual schema classes (FEAT-890)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add datetime import if missing
if 'from datetime import datetime' not in content:
    content = content.replace('import json', 'import json\nfrom datetime import datetime')
    if 'import json' not in content:
        # Add both
        content = 'import json\nfrom datetime import datetime\n' + content

charge_model_code = '''

# --- FEAT-890: Charge model and schema classes ---
class Charge:
    \"\"\"Represents a payment charge.\"\"\"
    def __init__(self, charge_id, amount, currency, status, created_at,
                 customer_email=None, payment_method_token=None,
                 stripe_fee=None, internal_notes=None, fraud_score=None):
        self.charge_id = charge_id
        self.amount = amount
        self.currency = currency
        self.status = status
        self.created_at = created_at
        self.customer_email = customer_email
        self.payment_method_token = payment_method_token
        self.stripe_fee = stripe_fee
        self.internal_notes = internal_notes
        self.fraud_score = fraud_score


class PublicChargeSchema:
    \"\"\"Public-facing schema — only safe fields for API consumers.\"\"\"
    FIELDS = ('charge_id', 'amount', 'currency', 'status', 'created_at')

    @staticmethod
    def dump(charge):
        return {
            'charge_id': charge.charge_id,
            'amount': str(charge.amount),
            'currency': charge.currency,
            'status': charge.status,
            'created_at': charge.created_at.strftime('%Y-%m-%d') if charge.created_at else None,
        }

    @classmethod
    def dump_many(cls, charges):
        return [cls.dump(c) for c in charges]


class FullChargeSchema:
    \"\"\"Full schema — all fields for admin dashboard and fraud review.\"\"\"
    FIELDS = ('charge_id', 'amount', 'currency', 'status', 'created_at',
              'customer_email', 'payment_method_token', 'stripe_fee',
              'internal_notes', 'fraud_score')

    @staticmethod
    def dump(charge):
        return {
            'charge_id': charge.charge_id,
            'amount': charge.amount,
            'currency': charge.currency,
            'status': charge.status,
            'created_at': charge.created_at.isoformat() if charge.created_at else None,
            'customer_email': charge.customer_email,
            'payment_method_token': charge.payment_method_token,
            'stripe_fee': charge.stripe_fee,
            'internal_notes': charge.internal_notes,
            'fraud_score': charge.fraud_score,
        }

    @classmethod
    def dump_many(cls, charges):
        return [cls.dump(c) for c in charges]


# In-memory charge store
_charges = []


@app.route('/admin/charges', methods=['GET'])
def admin_list_charges():
    \"\"\"Admin endpoint: returns all charge fields via FullChargeSchema.\"\"\"
    return jsonify({'charges': FullChargeSchema.dump_many(_charges)})


@app.route('/admin/charges/seed', methods=['GET'])
def admin_seed_charges():
    \"\"\"Seed sample charges for development.\"\"\"
    global _charges
    if _charges:
        return jsonify({'message': 'Already seeded', 'count': len(_charges)})
    _charges = [
        Charge(
            charge_id='ch_1NkR2e001', amount=4999, currency='usd',
            status='succeeded', created_at=datetime(2025, 3, 15, 10, 30, 0),
            customer_email='alice.johnson@example.com',
            payment_method_token='pm_tok_visa_4242_abc123',
            stripe_fee=175, internal_notes='VIP customer, expedited review',
            fraud_score=0.02,
        ),
        Charge(
            charge_id='ch_1NkR2e002', amount=12900, currency='usd',
            status='succeeded', created_at=datetime(2025, 3, 16, 14, 15, 0),
            customer_email='bob.smith@example.com',
            payment_method_token='pm_tok_mastercard_5555_def456',
            stripe_fee=403, internal_notes='Flagged by rule engine, manually cleared',
            fraud_score=0.67,
        ),
        Charge(
            charge_id='ch_1NkR2e003', amount=999, currency='eur',
            status='pending', created_at=None,
            customer_email=None, payment_method_token=None,
            stripe_fee=None, internal_notes=None, fraud_score=None,
        ),
    ]
    return jsonify({'message': f'Seeded {len(_charges)} charges'}), 201


'''

# Insert before the if __name__ block
if 'class Charge' not in content:
    content = content.replace(
        \"if __name__ == '__main__':\",
        charge_model_code + \"\nif __name__ == '__main__':\"
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added Charge model with PublicChargeSchema and FullChargeSchema')
print('  Added /admin/charges and /admin/charges/seed endpoints')
"

echo "Stage 1 complete."
