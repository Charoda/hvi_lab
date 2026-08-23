#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

TARGET="src/routes/v1/proxy.route.js"
python3 -c "
import pathlib
p = pathlib.Path('$TARGET')
t = p.read_text()

new = '''const express = require('express');
const http = require('http');
const https = require('https');
const router = express.Router();

// PROXY-1801: image proxy for partner CDNs
const ALLOWED_PROXY_HOSTS = new Set(['cdn.partner-a.com', 'img.partner-b.net', 'static.partner-c.io']);
const MAX_BYTES = 2 * 1024 * 1024;

function _validateProxyUrl(rawUrl) {
  const u = new URL(rawUrl);
  if (!['http:', 'https:'].includes(u.protocol)) throw new Error('bad protocol');
  if (!ALLOWED_PROXY_HOSTS.has(u.hostname)) throw new Error('host not allowed');
  return u;
}

async function _fetchStd(rawUrl, u, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const client = u.protocol === 'https:' ? https : http;
    const req = client.request(rawUrl, { headers: { 'User-Agent': 'MosaicImageProxy/1.0' }, timeout }, resolve);
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.end();
  });
}

router.get('/image', async (req, res) => {
  const rawUrl = req.query.url || '';
  let u;
  try { u = _validateProxyUrl(rawUrl); } catch (e) { return res.status(400).send(e.message); }

  let lastErr;
  for (const backoff of [0, 500, 1000]) {
    if (backoff) await new Promise(r => setTimeout(r, backoff));
    try {
      const upstream = await _fetchStd(rawUrl, u);
      const cl = upstream.headers['content-length'];
      if (cl && +cl > MAX_BYTES) return res.status(413).end();
      const ctype = upstream.headers['content-type'] || 'application/octet-stream';
      res.setHeader('Content-Type', ctype);
      let bytes = 0;
      let aborted = false;
      upstream.on('data', (chunk) => {
        if (aborted) return;
        bytes += chunk.length;
        if (bytes > MAX_BYTES) { aborted = true; upstream.destroy(); res.status(413).end(); return; }
        res.write(chunk);
      });
      upstream.on('end', () => { if (!aborted) res.end(); });
      return;
    } catch (e) { lastErr = e; }
  }
  res.status(502).send(String(lastErr && lastErr.message || 'upstream failure'));
});

module.exports = router;
'''
p.write_text(new)
print('  Rewrote with _validateProxyUrl helper + retry/backoff')
"
echo "Stage 2 complete."
