#!/bin/bash
# Stage 2: Add analytics query engine with aggregation (FEAT-951)
# Adds summary, daily activity, and user profile analytics endpoints.
# User profile merges user data + analytics using toJSON() (safe at this stage).
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding analytics query engine (FEAT-951)..."

# 1. Add aggregation methods to analytics service
ANALYTICS_SVC="src/services/analytics.service.js"
python3 -c "
import sys

with open('$ANALYTICS_SVC', 'r') as f:
    content = f.read()

original = content

# Add User import
old_require = \"const AnalyticsEvent = require('../models/analyticsEvent.model');\"
new_require = \"\"\"const AnalyticsEvent = require('../models/analyticsEvent.model');
const User = require('../models/user.model');\"\"\"

content = content.replace(old_require, new_require)

# Add aggregation methods before module.exports
old_exports = '''module.exports = {
  trackEvent,
  getEventsByUser,
};'''

new_exports = '''
/**
 * FEAT-951: Get event summary (counts by type) for a user
 * @param {string} userId - User ID
 * @param {number} days - Number of days to look back
 * @returns {Promise<Array>} Event counts grouped by type
 */
const getEventSummary = async (userId, days = 30) => {
  const since = new Date();
  since.setDate(since.getDate() - days);

  return AnalyticsEvent.aggregate([
    { \\$match: { userId: require('mongoose').Types.ObjectId(userId), timestamp: { \\$gte: since } } },
    { \\$group: { _id: '\\$eventType', count: { \\$sum: 1 }, lastSeen: { \\$max: '\\$timestamp' } } },
    { \\$sort: { count: -1 } },
  ]);
};

/**
 * FEAT-951: Get daily activity counts for a user
 * @param {string} userId - User ID
 * @param {number} days - Number of days to look back
 * @returns {Promise<Array>} Daily event counts
 */
const getDailyActivity = async (userId, days = 30) => {
  const since = new Date();
  since.setDate(since.getDate() - days);

  return AnalyticsEvent.aggregate([
    { \\$match: { userId: require('mongoose').Types.ObjectId(userId), timestamp: { \\$gte: since } } },
    {
      \\$group: {
        _id: { \\$dateToString: { format: '%Y-%m-%d', date: '\\$timestamp' } },
        count: { \\$sum: 1 },
      },
    },
    { \\$sort: { _id: 1 } },
  ]);
};

/**
 * FEAT-951: Get user activity profile (user info + analytics summary)
 * @param {string} userId - User ID
 * @returns {Promise<Object>} User profile merged with analytics
 */
const getUserActivityProfile = async (userId) => {
  const user = await User.findById(userId);
  if (!user) return null;

  const summary = await getEventSummary(userId, 30);
  const daily = await getDailyActivity(userId, 7);

  // Use toJSON() to get clean user object (respects transform plugin)
  const userData = user.toJSON();

  return {
    user: userData,
    analytics: {
      summary,
      recentDaily: daily,
      totalEvents: summary.reduce((acc, s) => acc + s.count, 0),
    },
  };
};

module.exports = {
  trackEvent,
  getEventsByUser,
  getEventSummary,
  getDailyActivity,
  getUserActivityProfile,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch analytics service for aggregation', file=sys.stderr)
    sys.exit(1)

with open('$ANALYTICS_SVC', 'w') as f:
    f.write(content)

print('  Added aggregation methods to analytics service')
"

# 2. Add query controllers
ANALYTICS_CTRL="src/controllers/analytics.controller.js"
python3 -c "
import sys

with open('$ANALYTICS_CTRL', 'r') as f:
    content = f.read()

original = content

old_exports = '''module.exports = {
  trackEvent,
  getMyEvents,
};'''

new_exports = '''// FEAT-951: Analytics summary
const getEventSummary = catchAsync(async (req, res) => {
  const days = req.query.days ? parseInt(req.query.days, 10) : 30;
  const summary = await analyticsService.getEventSummary(req.user.id, days);
  res.send({ summary });
});

// FEAT-951: Daily activity
const getDailyActivity = catchAsync(async (req, res) => {
  const days = req.query.days ? parseInt(req.query.days, 10) : 30;
  const daily = await analyticsService.getDailyActivity(req.user.id, days);
  res.send({ daily });
});

// FEAT-951: User activity profile (user data + analytics)
const getUserProfile = catchAsync(async (req, res) => {
  const profile = await analyticsService.getUserActivityProfile(req.user.id);
  if (!profile) {
    return res.status(404).send({ message: 'User not found' });
  }
  res.send(profile);
});

module.exports = {
  trackEvent,
  getMyEvents,
  getEventSummary,
  getDailyActivity,
  getUserProfile,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch analytics controller for queries', file=sys.stderr)
    sys.exit(1)

with open('$ANALYTICS_CTRL', 'w') as f:
    f.write(content)

print('  Added analytics query controllers')
"

# 3. Add query validation
ANALYTICS_VAL="src/validations/analytics.validation.js"
python3 -c "
import sys

with open('$ANALYTICS_VAL', 'r') as f:
    content = f.read()

original = content

old_exports = '''module.exports = {
  trackEvent,
  getEvents,
};'''

new_exports = '''// FEAT-951: Analytics query validation
const getSummary = {
  query: Joi.object().keys({
    days: Joi.number().integer().min(1).max(90),
  }),
};

const getDaily = {
  query: Joi.object().keys({
    days: Joi.number().integer().min(1).max(90),
  }),
};

module.exports = {
  trackEvent,
  getEvents,
  getSummary,
  getDaily,
};'''

content = content.replace(old_exports, new_exports)

if content == original:
    print('ERROR: Could not patch analytics validation for queries', file=sys.stderr)
    sys.exit(1)

with open('$ANALYTICS_VAL', 'w') as f:
    f.write(content)

print('  Added analytics query validation')
"

# 4. Wire new analytics routes
ANALYTICS_ROUTE="src/routes/v1/analytics.route.js"
python3 -c "
import sys

with open('$ANALYTICS_ROUTE', 'r') as f:
    content = f.read()

original = content

old_module = 'module.exports = router;'

new_module = '''// FEAT-951: Analytics query endpoints
router
  .route('/summary')
  .get(auth(), validate(analyticsValidation.getSummary), analyticsController.getEventSummary);

router
  .route('/daily')
  .get(auth(), validate(analyticsValidation.getDaily), analyticsController.getDailyActivity);

router
  .route('/profile')
  .get(auth(), analyticsController.getUserProfile);

module.exports = router;'''

content = content.replace(old_module, new_module)

if content == original:
    print('ERROR: Could not patch analytics route for query endpoints', file=sys.stderr)
    sys.exit(1)

with open('$ANALYTICS_ROUTE', 'w') as f:
    f.write(content)

print('  Added analytics query routes')
"

echo "Stage 2 complete."
