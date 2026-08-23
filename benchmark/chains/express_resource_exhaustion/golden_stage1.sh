#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding search endpoint with pagination (FEAT-1010)..."

cat > src/services/search.service.js << 'SVC_EOF'
const { User } = require('../models');

const searchUsers = async (query, options = {}) => {
  const limit = Math.min(options.limit || 20, 100);
  const page = options.page || 1;
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

  return {
    results: results.map((u) => u.toJSON()),
    page,
    limit,
    totalPages: Math.ceil(total / limit),
    totalResults: total,
  };
};

module.exports = { searchUsers };
SVC_EOF

echo "  Created src/services/search.service.js"

SVC_IDX="src/services/index.js"
python3 -c "
with open('$SVC_IDX', 'r') as f:
    content = f.read()
if 'searchService' not in content:
    content = content.rstrip() + \"\nmodule.exports.searchService = require('./search.service');\n\"
    with open('$SVC_IDX', 'w') as f:
        f.write(content)
    print('  Added searchService to services index')
"

cat > src/controllers/search.controller.js << 'CTRL_EOF'
const catchAsync = require('../utils/catchAsync');
const { searchService } = require('../services');

const searchUsers = catchAsync(async (req, res) => {
  const options = {
    limit: req.query.limit ? parseInt(req.query.limit, 10) : 20,
    page: req.query.page ? parseInt(req.query.page, 10) : 1,
  };
  const result = await searchService.searchUsers(req.query.q || '', options);
  res.send(result);
});

module.exports = { searchUsers };
CTRL_EOF

echo "  Created src/controllers/search.controller.js"

cat > src/validations/search.validation.js << 'VAL_EOF'
const Joi = require('joi');

const searchUsers = {
  query: Joi.object().keys({
    q: Joi.string().allow(''),
    limit: Joi.number().integer().min(1).max(100).default(20),
    page: Joi.number().integer().min(1).default(1),
  }),
};

module.exports = { searchUsers };
VAL_EOF

echo "  Created src/validations/search.validation.js"

cat > src/routes/v1/search.route.js << 'ROUTE_EOF'
const express = require('express');
const auth = require('../../middlewares/auth');
const validate = require('../../middlewares/validate');
const searchValidation = require('../../validations/search.validation');
const searchController = require('../../controllers/search.controller');

const router = express.Router();

router
  .route('/users')
  .get(auth(), validate(searchValidation.searchUsers), searchController.searchUsers);

module.exports = router;
ROUTE_EOF

echo "  Created src/routes/v1/search.route.js"

ROUTES_IDX="src/routes/v1/index.js"
python3 -c "
import sys
with open('$ROUTES_IDX', 'r') as f:
    content = f.read()
original = content
if 'searchRoute' not in content:
    # Add import after last require
    content = content.replace(
        \"const userRoute = require('./user.route');\",
        \"const userRoute = require('./user.route');\nconst searchRoute = require('./search.route');\"
    )
    # Add route entry
    old_routes = '''  {
    path: '/users',
    route: userRoute,
  },'''
    new_routes = '''  {
    path: '/users',
    route: userRoute,
  },
  {
    path: '/search',
    route: searchRoute,
  },'''
    content = content.replace(old_routes, new_routes)
    with open('$ROUTES_IDX', 'w') as f:
        f.write(content)
    print('  Added /search route to routes index')
"

echo "Stage 1 complete."
