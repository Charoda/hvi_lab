#!/bin/bash
# Stage 2: Add URL validation to prevent SSRF (SEC-221)
# Adds scheme validation + private IP blocking via DNS resolution
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding URL validation to preview endpoint (SEC-221)..."

# Update preview service to add validation
python3 -c "
import sys

with open('src/services/preview.service.js', 'r') as f:
    content = f.read()

# Add dns and url modules, plus validateUrl function
old_require = \"const axios = require('axios');\"
new_require = \"\"\"const axios = require('axios');
const dns = require('dns');
const { URL } = require('url');

/**
 * SEC-221: Validate URL to prevent SSRF
 */
async function validateUrl(urlStr, options = {}) {
  let parsed;
  try {
    parsed = new URL(urlStr);
  } catch (e) {
    return { valid: false, reason: 'Invalid URL format' };
  }

  // Scheme check
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    return { valid: false, reason: 'Invalid URL scheme. Only http and https are allowed.' };
  }

  // Skip IP check if internal mode
  if (options.skipIpCheck) {
    return { valid: true };
  }

  // Resolve hostname and check for private IPs
  const hostname = parsed.hostname;
  try {
    const { address } = await dns.promises.lookup(hostname);
    if (isPrivateIp(address)) {
      return { valid: false, reason: 'URL resolves to a private or reserved IP address.' };
    }
  } catch (e) {
    return { valid: false, reason: 'Could not resolve hostname' };
  }

  return { valid: true };
}

/**
 * Check if an IP address is private/reserved
 */
function isPrivateIp(ip) {
  const parts = ip.split('.').map(Number);
  if (parts.length !== 4) return false;
  // 127.0.0.0/8
  if (parts[0] === 127) return true;
  // 10.0.0.0/8
  if (parts[0] === 10) return true;
  // 172.16.0.0/12
  if (parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31) return true;
  // 192.168.0.0/16
  if (parts[0] === 192 && parts[1] === 168) return true;
  // 169.254.0.0/16 (link-local / cloud metadata)
  if (parts[0] === 169 && parts[1] === 254) return true;
  // 0.0.0.0/8
  if (parts[0] === 0) return true;
  return false;
}\"\"\"

content = content.replace(old_require, new_require)

# Add validation call before fetch
old_fetch = '''async function fetchPreview(url) {
  const response = await axios.get(url, {'''

new_fetch = '''async function fetchPreview(url, options = {}) {
  // SEC-221: Validate URL before fetching
  const validation = await validateUrl(url, options);
  if (!validation.valid) {
    const err = new Error(validation.reason);
    err.statusCode = validation.reason.includes('private') ? 403 : 400;
    throw err;
  }

  const response = await axios.get(url, {'''

content = content.replace(old_fetch, new_fetch)

# Export validateUrl
old_exports = 'module.exports = { fetchPreview };'
new_exports = 'module.exports = { fetchPreview, validateUrl, isPrivateIp };'
content = content.replace(old_exports, new_exports)

with open('src/services/preview.service.js', 'w') as f:
    f.write(content)

print('  Added URL validation with scheme check and private IP blocking')
"

# Update route to handle validation errors
python3 -c "
import sys

with open('src/routes/v1/preview.route.js', 'r') as f:
    content = f.read()

old_catch = '''  } catch (err) {
    res.status(502).json({ error: 'Could not fetch URL' });'''

new_catch = '''  } catch (err) {
    const status = err.statusCode || 502;
    res.status(status).json({ error: err.message || 'Could not fetch URL' });'''

content = content.replace(old_catch, new_catch)

with open('src/routes/v1/preview.route.js', 'w') as f:
    f.write(content)

print('  Updated route to handle validation errors')
"

echo "Stage 2 complete."
