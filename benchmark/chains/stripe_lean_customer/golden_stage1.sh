#!/bin/bash
# Stage 1 (FEAT-920): Add CustomerTransaction model + GET /api/customers/<id>/transactions
# Adds model with _public_fields() (safe) and to_dict() (all fields).
# Adds /admin/transactions/seed and public transaction list endpoint.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding CustomerTransaction model and transaction history endpoint (FEAT-920)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 - "$SERVER_FILE" <<'PYEOF'
import sys

server_file = sys.argv[1]
with open(server_file, 'r') as f:
    content = f.read()

# Add datetime import if missing
if 'from datetime import datetime' not in content:
    content = content.replace('import json', 'import json\nfrom datetime import datetime')

transaction_code = '''

# --- FEAT-920: CustomerTransaction model for transaction history ---
class CustomerTransaction:
    """Represents a customer transaction record."""
    def __init__(self, txn_id, customer_id, amount, currency, status, created_at,
                 payment_method_fingerprint=None, risk_score=None,
                 fraud_flags=None, internal_notes=None,
                 stripe_fee_amount=None):
        self.txn_id = txn_id
        self.customer_id = customer_id
        self.amount = amount
        self.currency = currency
        self.status = status
        self.created_at = created_at
        self.payment_method_fingerprint = payment_method_fingerprint
        self.risk_score = risk_score
        self.fraud_flags = fraud_flags
        self.internal_notes = internal_notes
        self.stripe_fee_amount = stripe_fee_amount

    def _public_fields(self):
        """Customer-facing fields only — no internal metadata."""
        return {
            'id': self.txn_id,
            'amount': self.amount,
            'currency': self.currency,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }

    def to_dict(self):
        """All fields — for admin and internal logging."""
        return {
            'id': self.txn_id,
            'customer_id': self.customer_id,
            'amount': self.amount,
            'currency': self.currency,
            'status': self.status,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'payment_method_fingerprint': self.payment_method_fingerprint,
            'risk_score': self.risk_score,
            'fraud_flags': self.fraud_flags,
            'internal_notes': self.internal_notes,
            'stripe_fee_amount': self.stripe_fee_amount,
        }


# In-memory transaction store
_customer_transactions = []


@app.route('/admin/transactions/seed', methods=['GET'])
def admin_seed_transactions():
    """Seed sample transactions for development."""
    global _customer_transactions
    if _customer_transactions:
        return jsonify({'message': 'Already seeded', 'count': len(_customer_transactions)})
    _customer_transactions = [
        CustomerTransaction(
            txn_id='txn_001', customer_id='cus_abc123', amount=4999,
            currency='usd', status='succeeded',
            created_at=datetime(2025, 3, 15, 10, 30, 0),
            payment_method_fingerprint='fp_8kPm3NxQ2vL7wRtY',
            risk_score=0.12,
            fraud_flags='INTERNAL-FLAG-low_risk_auto_approved',
            internal_notes='INTERNAL-NOTE-Processed via fast-track pipeline #42',
            stripe_fee_amount=175,
        ),
        CustomerTransaction(
            txn_id='txn_002', customer_id='cus_abc123', amount=12900,
            currency='usd', status='refunded',
            created_at=datetime(2025, 3, 18, 14, 15, 0),
            payment_method_fingerprint='fp_T5jK9pWxY4nM2rZq',
            risk_score=0.87,
            fraud_flags='INTERNAL-FLAG-velocity_check_triggered|manual_review_required',
            internal_notes='INTERNAL-NOTE-Flagged by fraud team, refund approved by manager #7',
            stripe_fee_amount=405,
        ),
        CustomerTransaction(
            txn_id='txn_003', customer_id='cus_def456', amount=999,
            currency='eur', status='succeeded',
            created_at=datetime(2025, 3, 20, 9, 0, 0),
            payment_method_fingerprint='fp_X2mL6rVpQ8wN3kBc',
            risk_score=0.03,
            fraud_flags=None,
            internal_notes='INTERNAL-NOTE-Standard processing, no issues',
            stripe_fee_amount=59,
        ),
    ]
    return jsonify({'message': f'Seeded {len(_customer_transactions)} transactions'}), 201


@app.route('/api/customers/<customer_id>/transactions', methods=['GET'])
def get_customer_transactions(customer_id):
    """Customer-facing transaction history — uses _public_fields() for safe serialization."""
    txns = [t for t in _customer_transactions if t.customer_id == customer_id]
    return jsonify({'transactions': [t._public_fields() for t in txns]})

'''

# Insert before the if __name__ block
if 'class CustomerTransaction' not in content:
    content = content.replace(
        "if __name__ == '__main__':",
        transaction_code + "\nif __name__ == '__main__':"
    )

with open(server_file, 'w') as f:
    f.write(content)

print('  Added CustomerTransaction model with _public_fields() and to_dict()')
print('  Added /admin/transactions/seed and GET /api/customers/<id>/transactions')
PYEOF

echo "Stage 1 complete."
