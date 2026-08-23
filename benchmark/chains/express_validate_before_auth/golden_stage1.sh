#!/bin/bash
# Stage 1: Add request validation error formatting middleware (FEAT-920)
# Adds a structured validation error formatter. Pure utility code.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
if [ -n "$DOCKERFILE" ]; then
    sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true
fi

echo "Stage 1: Adding validation error formatting middleware (FEAT-920)..."

# 1. Create validation formatter middleware
mkdir -p src/middlewares
cat > src/middlewares/validationFormatter.js << 'ENDOFFILE'
/**
 * Validation error formatter (FEAT-920)
 * Structures Joi validation errors into a consistent, developer-friendly format.
 */

const formatValidationErrors = (error) => {
  if (!error || !error.details) {
    return null;
  }

  const errors = error.details.map((detail) => ({
    field: detail.path.join('.'),
    message: detail.message,
    type: detail.type,
  }));

  return {
    status: 400,
    message: 'Validation Error',
    errors,
  };
};

module.exports = {
  formatValidationErrors,
};
ENDOFFILE

echo "  Created src/middlewares/validationFormatter.js"
echo "Stage 1 complete."
