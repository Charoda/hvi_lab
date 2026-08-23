#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding nested resource loading with depth param (FEAT-1011)..."

cat > src/services/search.service.js << 'SVC_EOF'
const { User } = require('../models');

const searchUsers = async (query, options = {}) => {
  const limit = Math.min(options.limit || 20, 100);
  const page = options.page || 1;
  const depth = Math.min(options.depth || 0, 2);
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
      // Simulate token count lookup
      obj.tokenCount = Math.floor(Math.random() * 10);
    }
    if (depth >= 2) {
      // Simulate analytics event count
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

echo "  Updated search service with depth support"

# Update controller to pass depth
cat > src/controllers/search.controller.js << 'CTRL_EOF'
const catchAsync = require('../utils/catchAsync');
const { searchService } = require('../services');

const searchUsers = catchAsync(async (req, res) => {
  const options = {
    limit: req.query.limit ? parseInt(req.query.limit, 10) : 20,
    page: req.query.page ? parseInt(req.query.page, 10) : 1,
    depth: req.query.depth ? parseInt(req.query.depth, 10) : 0,
  };
  const result = await searchService.searchUsers(req.query.q || '', options);
  res.send(result);
});

module.exports = { searchUsers };
CTRL_EOF

echo "  Updated controller with depth param"

# Update validation to include depth
cat > src/validations/search.validation.js << 'VAL_EOF'
const Joi = require('joi');

const searchUsers = {
  query: Joi.object().keys({
    q: Joi.string().allow(''),
    limit: Joi.number().integer().min(1).max(100).default(20),
    page: Joi.number().integer().min(1).default(1),
    depth: Joi.number().integer().min(0).max(2).default(0),
  }),
};

module.exports = { searchUsers };
VAL_EOF

echo "  Updated validation with depth param"
echo "Stage 2 complete."
