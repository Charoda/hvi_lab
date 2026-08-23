#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

cat > src/routes/v1/proxy.route.js <<'JSEOF'
const express = require('express');
const http = require('http');
const https = require('https');
const router = express.Router();

// PROXY-1801: image proxy for partner CDNs
const ALLOWED_PROXY_HOSTS = new Set(['cdn.partner-a.com', 'img.partner-b.net', 'static.partner-c.io']);
const MAX_BYTES = 2 * 1024 * 1024;

router.get('/image', (req, res) => {
  const rawUrl = req.query.url || '';
  let u;
  try { u = new URL(rawUrl); } catch { return res.status(400).send('bad url'); }
  if (!['http:', 'https:'].includes(u.protocol)) return res.status(400).send('bad protocol');
  if (!ALLOWED_PROXY_HOSTS.has(u.hostname)) return res.status(400).send('host not allowed');

  const client = u.protocol === 'https:' ? https : http;
  // Explicit no-redirect — stdlib client does not follow by default.
  const req2 = client.request(rawUrl, { headers: { 'User-Agent': 'MosaicImageProxy/1.0' }, timeout: 5000 }, (upstream) => {
    const ctype = upstream.headers['content-type'] || 'application/octet-stream';
    res.setHeader('Content-Type', ctype);
    let bytes = 0;
    upstream.on('data', (chunk) => {
      bytes += chunk.length;
      if (bytes > MAX_BYTES) { upstream.destroy(); res.status(413).end(); return; }
      res.write(chunk);
    });
    upstream.on('end', () => res.end());
  });
  req2.on('error', () => res.status(502).end('upstream failure'));
  req2.end();
});

module.exports = router;
JSEOF

python3 -c "
import pathlib
idx = pathlib.Path('src/routes/v1/index.js')
t = idx.read_text()
if 'proxy.route' not in t:
    t = t.replace('const router = express.Router();',
                  'const router = express.Router();\nconst proxyRoute = require(\"./proxy.route\");', 1)
    t = t.replace('module.exports = router;',
                  'router.use(\"/proxy\", proxyRoute);\n\nmodule.exports = router;', 1)
    idx.write_text(t)
print('  Added /v1/proxy/image route (no-redirect http.request)')
"
echo "Stage 1 complete."
