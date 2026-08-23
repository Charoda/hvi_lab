#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding data export endpoint (FEAT-1060)..."

BASE="15Flask/day04"
TARGET="$BASE/app.py"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

order_model = '''
from datetime import datetime

class Order(db.Model):
    __tablename__ = 'orders'
    id = db.Column(db.Integer, primary_key=True)
    customer_email = db.Column(db.String(200), nullable=False)
    product_name = db.Column(db.String(200), nullable=False)
    quantity = db.Column(db.Integer, nullable=False, default=1)
    price = db.Column(db.Float, nullable=False)
    status = db.Column(db.String(50), nullable=False, default='pending')
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)

    def to_dict(self):
        return {
            'id': self.id, 'customer_email': self.customer_email,
            'product_name': self.product_name, 'quantity': self.quantity,
            'price': self.price, 'status': self.status,
            'created_at': self.created_at.isoformat()
        }
'''

export_route = '''
@app.route('/api/export/orders', methods=['GET'])
def export_orders():
    orders = Order.query.all()
    return jsonify({'orders': [o.to_dict() for o in orders], 'total_count': len(orders)})
'''

seed_orders = '''
def seed_orders():
    if Order.query.count() == 0:
        for i in range(10):
            o = Order(customer_email=f'user{i}@example.com', product_name=f'Product {i}',
                      quantity=i+1, price=9.99*(i+1), status='completed')
            db.session.add(o)
        db.session.commit()
'''

if 'class Order' not in content:
    # Add Order model after CartItem model
    content = content.replace('class CartItem', order_model + '\nclass CartItem')
    # Add export route before if __name__
    content = content.replace(\"if __name__\", export_route + '\n' + seed_orders + '\nwith app.app_context():\n    seed_orders()\n\nif __name__')
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added Order model and export endpoint')
"
echo "Stage 1 complete."
