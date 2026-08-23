#!/bin/bash
# Stage 2 (FEAT-1601): Add transaction history and receipts.
# Creates:
#   - src/models/transaction.model.js — Transaction schema
# Patches:
#   - src/models/index.js — register Transaction model
#   - src/services/wallet.service.js — add transaction logging to withdraw
#   - src/controllers/wallet.controller.js — add getTransactions handler
#   - src/routes/v1/user.route.js — add transactions route
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding transaction history and receipts (FEAT-1601)..."

# 1. Create Transaction model
cat > src/models/transaction.model.js << 'EOF'
const mongoose = require('mongoose');
const { toJSON } = require('./plugins');

const transactionSchema = mongoose.Schema(
  {
    userId: {
      type: mongoose.SchemaTypes.ObjectId,
      ref: 'User',
      required: true,
    },
    type: {
      type: String,
      required: true,
      default: 'withdrawal',
    },
    amount: {
      type: Number,
      required: true,
    },
    balanceBefore: {
      type: Number,
      required: true,
    },
    balanceAfter: {
      type: Number,
      required: true,
    },
    receiptId: {
      type: String,
      required: true,
      unique: true,
    },
    status: {
      type: String,
      default: 'completed',
    },
  },
  {
    timestamps: true,
  }
);

transactionSchema.plugin(toJSON);

const Transaction = mongoose.model('Transaction', transactionSchema);

module.exports = Transaction;
EOF

echo "  Created src/models/transaction.model.js"

# 2. Register Transaction model in models index
python3 -c "
with open('src/models/index.js', 'r') as f:
    content = f.read()

if 'Transaction' not in content:
    content = content.rstrip() + \"\nmodule.exports.Transaction = require('./transaction.model');\n\"

with open('src/models/index.js', 'w') as f:
    f.write(content)

print('  Registered Transaction in models/index.js')
"

# 3. Update wallet service to log transactions
python3 -c "
import sys

with open('src/services/wallet.service.js', 'r') as f:
    content = f.read()

original = content

# Add Transaction require
old_require = \"const { User } = require('../models');\"
new_require = \"const { User, Transaction } = require('../models');\"
content = content.replace(old_require, new_require)

# Replace withdraw function with transaction-logging version
old_withdraw = '''const withdraw = async (userId, amount) => {
  const user = await User.findById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  if (user.balance < amount) {
    throw new ApiError(httpStatus.BAD_REQUEST, 'Insufficient funds');
  }
  user.balance -= amount;
  await user.save();
  return user.balance;
};'''

new_withdraw = '''const withdraw = async (userId, amount) => {
  const user = await User.findById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  if (user.balance < amount) {
    throw new ApiError(httpStatus.BAD_REQUEST, 'Insufficient funds');
  }

  // FEAT-1601: Log transaction before deduction
  const receiptId = \`receipt_\${Date.now()}_\${Math.random().toString(36).slice(2, 8)}\`;
  const balanceBefore = user.balance;
  await Transaction.create({
    userId,
    type: 'withdrawal',
    amount,
    balanceBefore,
    balanceAfter: balanceBefore - amount,
    receiptId,
    status: 'completed',
  });

  user.balance -= amount;
  await user.save();
  return { balance: user.balance, withdrawn: amount, receiptId };
};

/**
 * Get transaction history for a user
 * @param {ObjectId} userId
 * @returns {Promise<Array>}
 */
const getTransactions = async (userId) => {
  const user = await User.findById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  return Transaction.find({ userId }).sort({ createdAt: -1 });
};'''

content = content.replace(old_withdraw, new_withdraw)

# Update exports
old_exports = '''module.exports = {
  getBalance,
  withdraw,
};'''

new_exports = '''module.exports = {
  getBalance,
  withdraw,
  getTransactions,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch wallet service', file=sys.stderr)
    sys.exit(1)

with open('src/services/wallet.service.js', 'w') as f:
    f.write(content)

print('  Updated wallet service with transaction logging')
"

# 4. Update wallet controller to return receiptId and add transactions endpoint
python3 -c "
import sys

with open('src/controllers/wallet.controller.js', 'r') as f:
    content = f.read()

original = content

# Replace withdraw handler to pass through the full result object
old_withdraw = '''const withdraw = catchAsync(async (req, res) => {
  const { amount } = req.body;
  const balance = await walletService.withdraw(req.params.userId, amount);
  res.send({ balance, withdrawn: amount });
});'''

new_withdraw = '''const withdraw = catchAsync(async (req, res) => {
  const { amount } = req.body;
  const result = await walletService.withdraw(req.params.userId, amount);
  res.send(result);
});

const getTransactions = catchAsync(async (req, res) => {
  const transactions = await walletService.getTransactions(req.params.userId);
  res.send(transactions);
});'''

content = content.replace(old_withdraw, new_withdraw)

# Update exports
old_exports = '''module.exports = {
  getBalance,
  withdraw,
};'''

new_exports = '''module.exports = {
  getBalance,
  withdraw,
  getTransactions,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch wallet controller', file=sys.stderr)
    sys.exit(1)

with open('src/controllers/wallet.controller.js', 'w') as f:
    f.write(content)

print('  Updated wallet controller with transactions endpoint')
"

# 5. Add transactions route
python3 -c "
import sys

with open('src/routes/v1/user.route.js', 'r') as f:
    content = f.read()

original = content

# Add transactions route before module.exports
old_module = 'module.exports = router;'

new_module = '''// FEAT-1601: Transaction history
router
  .route('/:userId/wallet/transactions')
  .get(auth('getUsers'), validate(userValidation.getUser), walletController.getTransactions);

module.exports = router;'''

content = content.replace(old_module, new_module)

if content == original:
    print('ERROR: Could not patch routes for transactions', file=sys.stderr)
    sys.exit(1)

with open('src/routes/v1/user.route.js', 'w') as f:
    f.write(content)

print('  Added transactions route')
"

echo "Stage 2 complete."
