#!/bin/bash
# Stage 3 (BUG-600): Add payment provider confirmation delay.
# Inserts an async delay between balance check and deduction.
#
# THE VULNERABILITY (CWE-362 — TOCTOU Race Condition):
# The withdraw function reads user.balance from MongoDB, checks it,
# then awaits a 200ms simulated provider call. During that await,
# Node.js yields to the event loop. Other concurrent withdraw requests
# read the SAME pre-deduction balance from MongoDB, all pass the check,
# and each deducts. Result: N concurrent requests on balance B each
# deduct A, leaving balance B - N*A (potentially negative).
#
# This is a classic TOCTOU (Time-of-Check-Time-of-Use) vulnerability.
# The "check" (balance >= amount) and the "use" (balance -= amount)
# are separated by an async gap.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding payment provider confirmation delay (BUG-600)..."

# Add confirmWithProvider and insert it into the withdraw flow
python3 -c "
import sys

with open('src/services/wallet.service.js', 'r') as f:
    content = f.read()

original = content

# Add confirmWithProvider helper after the requires
old_getbalance = '''/**
 * Get user balance'''

new_getbalance = '''/**
 * Simulate external payment provider confirmation.
 * In production this would be an HTTP call to Stripe/bank API.
 * @param {number} amount
 * @param {string} receiptId
 * @returns {Promise<Object>}
 */
const confirmWithProvider = (amount, receiptId) => {
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({ confirmed: true, providerRef: \`prov_\${receiptId}\` });
    }, 200);
  });
};

/**
 * Get user balance'''

content = content.replace(old_getbalance, new_getbalance)

# Insert the confirmWithProvider call between transaction logging and deduction
old_deduct = '''  user.balance -= amount;
  await user.save();
  return { balance: user.balance, withdrawn: amount, receiptId };'''

new_deduct = '''  // BUG-600: Confirm with payment provider before committing
  await confirmWithProvider(amount, receiptId);

  user.balance -= amount;
  await user.save();
  return { balance: user.balance, withdrawn: amount, receiptId };'''

content = content.replace(old_deduct, new_deduct)

if content == original:
    print('ERROR: Could not patch wallet service for provider confirmation', file=sys.stderr)
    sys.exit(1)

with open('src/services/wallet.service.js', 'w') as f:
    f.write(content)

print('  Added confirmWithProvider delay between balance check and deduction')
"

echo "Stage 3 complete."
