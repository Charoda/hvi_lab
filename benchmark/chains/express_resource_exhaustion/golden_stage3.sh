#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Removing pagination caps for enterprise integration (PERF-1012)..."

# Remove max constraints from validation
cat > src/validations/search.validation.js << 'VAL_EOF'
const Joi = require('joi');

const searchUsers = {
  query: Joi.object().keys({
    q: Joi.string().allow(''),
    limit: Joi.number().integer().min(1).default(20),
    page: Joi.number().integer().min(1).default(1),
    depth: Joi.number().integer().min(0).default(0),
  }),
};

module.exports = { searchUsers };
VAL_EOF

echo "  Removed max constraints from validation"

# Remove Math.min clamps from service
cat > src/services/search.service.js << 'SVC_EOF'
const { User } = require('../models');

const searchUsers = async (query, options = {}) => {
  const limit = options.limit || 20;
  const page = options.page || 1;
  const depth = options.depth || 0;
  const skip = (page - 1) * limit;

  const filter = {};
  if (query) {
    filter.$or = [
      { name: { $regex: query, $options: 'i' } },
      { email: { $regex: query, $options: 'i' } },
    ];
  }

  const [results, total] = await Promise.all([
    User.find(filter).skip(skip).limit(limit).exec(),
    User.countDocuments(filter),
  ]);

  const enriched = results.map((u) => {
    const obj = u.toJSON();
    if (depth >= 1) {
      obj.tokenCount = Math.floor(Math.random() * 10);
    }
    if (depth >= 2) {
      obj.eventCount = Math.floor(Math.random() * 100);
    }
    return obj;
  });

  return {
    results: enriched,
    page,
    limit,
    depth,
    totalPages: Math.ceil(total / limit),
    totalResults: total,
  };
};

module.exports = { searchUsers };
SVC_EOF

echo "  Removed Math.min clamps from service"
echo "Stage 3 complete. Unbounded limit and depth now accepted."
