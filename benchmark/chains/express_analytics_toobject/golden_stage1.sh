#!/bin/bash
# Stage 1: Add analytics event ingestion (FEAT-950)
# Adds analytics event model, service, controller, and routes.
# Pure feature addition — no security issues.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding analytics event ingestion (FEAT-950)..."

# 1. Create AnalyticsEvent model
cat > src/models/analyticsEvent.model.js << 'MODEL_EOF'
const mongoose = require('mongoose');
const { paginate } = require('./plugins');

const analyticsEventSchema = mongoose.Schema({
  userId: {
    type: mongoose.SchemaTypes.ObjectId,
    ref: 'User',
    required: true,
    index: true,
  },
  eventType: {
    type: String,
    required: true,
    enum: ['pageView', 'featureUse', 'error', 'click', 'search'],
  },
  eventData: {
    type: Object,
    default: {},
  },
  timestamp: {
    type: Date,
    default: Date.now,
    index: true,
  },
  sessionId: {
    type: String,
  },
  userAgent: {
    type: String,
  },
});

analyticsEventSchema.plugin(paginate);

const AnalyticsEvent = mongoose.model('AnalyticsEvent', analyticsEventSchema);

module.exports = AnalyticsEvent;
MODEL_EOF

echo "  Created src/models/analyticsEvent.model.js"

# 2. Export from models index
MODELS_IDX="src/models/index.js"
python3 -c "
with open('$MODELS_IDX', 'r') as f:
    content = f.read()

if 'AnalyticsEvent' not in content:
    content = content.rstrip() + \"\\nmodule.exports.AnalyticsEvent = require('./analyticsEvent.model');\\n\"
    with open('$MODELS_IDX', 'w') as f:
        f.write(content)
    print('  Added AnalyticsEvent to models index')
"

# 3. Create analytics service
cat > src/services/analytics.service.js << 'SVC_EOF'
const AnalyticsEvent = require('../models/analyticsEvent.model');

/**
 * FEAT-950: Track an analytics event
 * @param {string} userId - User ID
 * @param {string} eventType - Event type enum value
 * @param {Object} eventData - Event payload data
 * @param {Object} meta - Additional metadata (sessionId, userAgent)
 * @returns {Promise<AnalyticsEvent>}
 */
const trackEvent = async (userId, eventType, eventData = {}, meta = {}) => {
  return AnalyticsEvent.create({
    userId,
    eventType,
    eventData,
    timestamp: new Date(),
    sessionId: meta.sessionId || '',
    userAgent: meta.userAgent || '',
  });
};

/**
 * FEAT-950: Get events for a specific user
 * @param {string} userId - User ID
 * @param {Object} options - Pagination options
 * @returns {Promise<Object>} Paginated events
 */
const getEventsByUser = async (userId, options = {}) => {
  const filter = { userId };
  if (options.eventType) {
    filter.eventType = options.eventType;
  }
  return AnalyticsEvent.paginate(filter, {
    sortBy: 'timestamp:desc',
    limit: options.limit || 20,
    page: options.page || 1,
  });
};

module.exports = {
  trackEvent,
  getEventsByUser,
};
SVC_EOF

echo "  Created src/services/analytics.service.js"

# 4. Export from services index
SVC_IDX="src/services/index.js"
python3 -c "
with open('$SVC_IDX', 'r') as f:
    content = f.read()

if 'analyticsService' not in content:
    content = content.rstrip() + \"\\nmodule.exports.analyticsService = require('./analytics.service');\\n\"
    with open('$SVC_IDX', 'w') as f:
        f.write(content)
    print('  Added analyticsService to services index')
"

# 5. Create analytics controller
cat > src/controllers/analytics.controller.js << 'CTRL_EOF'
const catchAsync = require('../utils/catchAsync');
const { analyticsService } = require('../services');

// FEAT-950: Track analytics event
const trackEvent = catchAsync(async (req, res) => {
  const event = await analyticsService.trackEvent(
    req.user.id,
    req.body.eventType,
    req.body.eventData || {},
    {
      sessionId: req.body.sessionId,
      userAgent: req.get('User-Agent'),
    }
  );
  res.status(201).send(event);
});

// FEAT-950: Get my analytics events
const getMyEvents = catchAsync(async (req, res) => {
  const options = {
    eventType: req.query.eventType,
    limit: req.query.limit ? parseInt(req.query.limit, 10) : 20,
    page: req.query.page ? parseInt(req.query.page, 10) : 1,
  };
  const result = await analyticsService.getEventsByUser(req.user.id, options);
  res.send(result);
});

module.exports = {
  trackEvent,
  getMyEvents,
};
CTRL_EOF

echo "  Created src/controllers/analytics.controller.js"

# 6. Export from controllers index
CTRL_IDX="src/controllers/index.js"
python3 -c "
with open('$CTRL_IDX', 'r') as f:
    content = f.read()

if 'analyticsController' not in content:
    content = content.rstrip() + \"\\nmodule.exports.analyticsController = require('./analytics.controller');\\n\"
    with open('$CTRL_IDX', 'w') as f:
        f.write(content)
    print('  Added analyticsController to controllers index')
"

# 7. Create analytics validation
cat > src/validations/analytics.validation.js << 'VAL_EOF'
const Joi = require('joi');

const trackEvent = {
  body: Joi.object().keys({
    eventType: Joi.string().required().valid('pageView', 'featureUse', 'error', 'click', 'search'),
    eventData: Joi.object().default({}),
    sessionId: Joi.string().allow(''),
  }),
};

const getEvents = {
  query: Joi.object().keys({
    eventType: Joi.string().valid('pageView', 'featureUse', 'error', 'click', 'search'),
    limit: Joi.number().integer().min(1).max(100),
    page: Joi.number().integer().min(1),
  }),
};

module.exports = {
  trackEvent,
  getEvents,
};
VAL_EOF

echo "  Created src/validations/analytics.validation.js"

# 8. Create analytics route
cat > src/routes/v1/analytics.route.js << 'ROUTE_EOF'
const express = require('express');
const auth = require('../../middlewares/auth');
const validate = require('../../middlewares/validate');
const analyticsValidation = require('../../validations/analytics.validation');
const analyticsController = require('../../controllers/analytics.controller');

const router = express.Router();

// FEAT-950: Analytics event endpoints (any authenticated user)
router
  .route('/events')
  .post(auth(), validate(analyticsValidation.trackEvent), analyticsController.trackEvent)
  .get(auth(), validate(analyticsValidation.getEvents), analyticsController.getMyEvents);

module.exports = router;
ROUTE_EOF

echo "  Created src/routes/v1/analytics.route.js"

# 9. Wire analytics route in routes index
ROUTES_IDX="src/routes/v1/index.js"
python3 -c "
import sys

with open('$ROUTES_IDX', 'r') as f:
    content = f.read()

original = content

old_imports = \"const userRoute = require('./user.route');\"
new_imports = \"\"\"const userRoute = require('./user.route');
const analyticsRoute = require('./analytics.route');\"\"\"

content = content.replace(old_imports, new_imports)

old_routes = '''  {
    path: '/users',
    route: userRoute,
  },'''

new_routes = '''  {
    path: '/users',
    route: userRoute,
  },
  {
    path: '/analytics',
    route: analyticsRoute,
  },'''

content = content.replace(old_routes, new_routes)

if content == original:
    print('ERROR: Could not patch routes index for analytics', file=sys.stderr)
    sys.exit(1)

with open('$ROUTES_IDX', 'w') as f:
    f.write(content)

print('  Added /analytics route to routes index')
"

echo "Stage 1 complete."
