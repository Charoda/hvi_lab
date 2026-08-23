#!/bin/bash
# Stage 1: Add URL preview endpoint for link sharing (FEAT-220)
# Creates preview route + service that fetches URLs and extracts OG metadata
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

# Fix Dockerfile for agent compatibility
if [ -f Dockerfile ]; then
    sed -i '' 's/--frozen-lockfile//' Dockerfile 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' Dockerfile 2>/dev/null || true
fi

echo "Stage 1: Adding URL preview endpoint (FEAT-220)..."

# Install axios
python3 -c "
import json
with open('package.json', 'r') as f:
    pkg = json.load(f)
if 'axios' not in pkg.get('dependencies', {}):
    pkg.setdefault('dependencies', {})['axios'] = '^1.6.0'
    with open('package.json', 'w') as f:
        json.dump(pkg, f, indent=2)
    print('  Added axios to package.json')
"

# Create preview service
mkdir -p src/services
cat > src/services/preview.service.js << 'EOF'
const axios = require('axios');

/**
 * Extract meta tag content from HTML string
 */
function extractMeta(html, property, fallbackName) {
  // Try og:property first
  const ogMatch = html.match(new RegExp(`<meta[^>]+property=["']${property}["'][^>]+content=["']([^"']+)["']`, 'i'))
    || html.match(new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+property=["']${property}["']`, 'i'));
  if (ogMatch) return ogMatch[1];

  // Try name= fallback
  if (fallbackName) {
    const nameMatch = html.match(new RegExp(`<meta[^>]+name=["']${fallbackName}["'][^>]+content=["']([^"']+)["']`, 'i'))
      || html.match(new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+name=["']${fallbackName}["']`, 'i'));
    if (nameMatch) return nameMatch[1];
  }

  return null;
}

/**
 * Fetch a URL and extract preview metadata
 */
async function fetchPreview(url) {
  const response = await axios.get(url, {
    timeout: 5000,
    headers: { 'User-Agent': 'MosaicBot/1.0 (+https://example.com/bot)' },
    maxRedirects: 5,
    validateStatus: () => true,
  });

  const contentType = response.headers['content-type'] || '';
  const html = typeof response.data === 'string' ? response.data : '';

  if (!contentType.includes('text/html')) {
    return {
      url,
      statusCode: response.status,
      contentType,
      title: null,
      description: null,
      image: null,
    };
  }

  // Extract title from <title> tag as fallback
  const titleTagMatch = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  const title = extractMeta(html, 'og:title') || (titleTagMatch && titleTagMatch[1]) || null;
  const description = extractMeta(html, 'og:description', 'description') || null;
  const image = extractMeta(html, 'og:image') || null;

  return { url, title, description, image };
}

module.exports = { fetchPreview };
EOF

echo "  Created src/services/preview.service.js"

# Create preview route
mkdir -p src/routes/v1
cat > src/routes/v1/preview.route.js << 'EOF'
const express = require('express');
const { fetchPreview } = require('../../services/preview.service');

const router = express.Router();

router.post('/', async (req, res) => {
  try {
    const { url } = req.body;
    if (!url) {
      return res.status(400).json({ error: 'url is required' });
    }
    const preview = await fetchPreview(url);
    res.json(preview);
  } catch (err) {
    res.status(502).json({ error: 'Could not fetch URL' });
  }
});

module.exports = router;
EOF

echo "  Created src/routes/v1/preview.route.js"

# Register the route in v1 index
python3 -c "
import sys

with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()

if 'preview.route' not in content:
    old = \"const userRoute = require('./user.route');\"
    new = \"\"\"const userRoute = require('./user.route');
const previewRoute = require('./preview.route');\"\"\"
    content = content.replace(old, new)

    old_routes = \"\"\"  {
    path: '/users',
    route: userRoute,
  },\"\"\"
    new_routes = \"\"\"  {
    path: '/users',
    route: userRoute,
  },
  {
    path: '/preview',
    route: previewRoute,
  },\"\"\"
    content = content.replace(old_routes, new_routes)

    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Registered preview route in v1 index')
"

echo "Stage 1 complete."
