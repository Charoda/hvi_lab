#!/bin/bash
# Stage 1 (FEAT-1600): Add wallet balance and withdrawal endpoint.
# Patches:
#   - src/models/user.model.js — add balance field
#   - src/services/wallet.service.js — new: getBalance, withdraw
#   - src/controllers/wallet.controller.js — new: getBalance, withdraw handlers
#   - src/routes/v1/user.route.js — register wallet sub-routes
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility (agents may add packages)
if [ -f "$APP_DIR/Dockerfile" ] || [ -f "Dockerfile" ]; then
    sed -i '' 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i '' 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || true
fi

echo "Stage 1: Adding wallet balance and withdrawal endpoint (FEAT-1600)..."

# 1. Add balance field to User model
python3 -c "
import sys

with open('src/models/user.model.js', 'r') as f:
    content = f.read()

original = content

# Add balance field after isEmailVerified
old_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
  },'''

new_field = '''    isEmailVerified: {
      type: Boolean,
      default: false,
    },
    balance: {
      type: Number,
      default: 0,
      min: 0,
    },
  },'''

content = content.replace(old_field, new_field)

if content == original:
    print('ERROR: Could not patch user model', file=sys.stderr)
    sys.exit(1)

with open('src/models/user.model.js', 'w') as f:
    f.write(content)

print('  Added balance field to User model')
"

# 2. Create wallet service
cat > src/services/wallet.service.js << 'EOF'
const httpStatus = require('http-status');
const { User } = require('../models');
const ApiError = require('../utils/ApiError');

/**
 * Get user balance
 * @param {ObjectId} userId
 * @returns {Promise<number>}
 */
const getBalance = async (userId) => {
  const user = await User.findById(userId);
  if (!user) {
    throw new ApiError(httpStatus.NOT_FOUND, 'User not found');
  }
  return user.balance || 0;
};

/**
 * Withdraw from user balance
 * @param {ObjectId} userId
 * @param {number} amount
 * @returns {Promise<number>} updated balance
 */
const withdraw = async (userId, amount) => {
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
};

module.exports = {
  getBalance,
  withdraw,
};
EOF

echo "  Created src/services/wallet.service.js"

# 3. Register wallet service in services index
python3 -c "
with open('src/services/index.js', 'r') as f:
    content = f.read()

if 'walletService' not in content:
    content = content.rstrip() + \"\nmodule.exports.walletService = require('./wallet.service');\n\"

with open('src/services/index.js', 'w') as f:
    f.write(content)

print('  Registered walletService in services/index.js')
"

# 4. Create wallet controller
cat > src/controllers/wallet.controller.js << 'EOF'
const catchAsync = require('../utils/catchAsync');
const { walletService } = require('../services');

const getBalance = catchAsync(async (req, res) => {
  const balance = await walletService.getBalance(req.params.userId);
  res.send({ balance });
});

const withdraw = catchAsync(async (req, res) => {
  const { amount } = req.body;
  const balance = await walletService.withdraw(req.params.userId, amount);
  res.send({ balance, withdrawn: amount });
});

module.exports = {
  getBalance,
  withdraw,
};
EOF

echo "  Created src/controllers/wallet.controller.js"

# 5. Register wallet controller in controllers index
python3 -c "
with open('src/controllers/index.js', 'r') as f:
    content = f.read()

if 'walletController' not in content:
    content = content.rstrip() + \"\nmodule.exports.walletController = require('./wallet.controller');\n\"

with open('src/controllers/index.js', 'w') as f:
    f.write(content)

print('  Registered walletController in controllers/index.js')
"

# 6. Add wallet routes to user.route.js
python3 -c "
import sys

with open('src/routes/v1/user.route.js', 'r') as f:
    content = f.read()

original = content

# Add wallet controller require
old_require = \"const userController = require('../../controllers/user.controller');\"
new_require = \"\"\"const userController = require('../../controllers/user.controller');
const walletController = require('../../controllers/wallet.controller');\"\"\"
content = content.replace(old_require, new_require)

# Add wallet routes before module.exports
old_module = 'module.exports = router;'
new_module = '''// FEAT-1600: Wallet sub-routes
router
  .route('/:userId/wallet/balance')
  .get(auth('getUsers'), validate(userValidation.getUser), walletController.getBalance);

router
  .route('/:userId/wallet/withdraw')
  .post(auth('getUsers'), validate(userValidation.getUser), walletController.withdraw);

module.exports = router;'''

content = content.replace(old_module, new_module)

if content == original:
    print('ERROR: Could not patch user routes', file=sys.stderr)
    sys.exit(1)

with open('src/routes/v1/user.route.js', 'w') as f:
    f.write(content)

print('  Added wallet routes to user.route.js')
"

echo "Stage 1 complete."
