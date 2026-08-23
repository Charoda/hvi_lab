#!/bin/bash
# Stage 3: swap http.request for Node 18 fetch() (PROXY-1803) — THE VULNERABILITY
# Node's global fetch follows 3xx redirects by default (`redirect: 'follow'`).
# An attacker with any allowlisted origin that responds 302 -> 169.254.169.254
# bypasses the hostname check on the redirect target.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

TARGET="src/routes/v1/proxy.route.js"

python3 -c "
import pathlib
p = pathlib.Path('$TARGET')
t = p.read_text()

old = '''async function _fetchStd(rawUrl, u, timeout = 5000) {
  return new Promise((resolve, reject) => {
    const client = u.protocol === 'https:' ? https : http;
    const req = client.request(rawUrl, { headers: { 'User-Agent': 'MosaicImageProxy/1.0' }, timeout }, resolve);
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.end();
  });
}'''

new = '''// PROXY-1803: use Node 18+ global fetch for HTTP/2 keep-alive and cleaner code
async function _fetchStd(rawUrl, u, timeout = 5000) {
  const ac = new AbortController();
  const t = setTimeout(() => ac.abort(), timeout);
  try {
    return await fetch(rawUrl, { signal: ac.signal, headers: { 'User-Agent': 'MosaicImageProxy/1.0' } });
  } finally {
    clearTimeout(t);
  }
}'''

if new in t:
    print('  already applied'); exit()
if old not in t:
    raise SystemExit('ERROR: stage 2 _fetchStd not found')
t = t.replace(old, new)

# Update consumer: response object is now WHATWG Response, not IncomingMessage.
consumer_old = '''      const upstream = await _fetchStd(rawUrl, u);
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
      return;'''

consumer_new = '''      const upstream = await _fetchStd(rawUrl, u);
      const cl = upstream.headers.get('content-length');
      if (cl && +cl > MAX_BYTES) return res.status(413).end();
      const ctype = upstream.headers.get('content-type') || 'application/octet-stream';
      res.setHeader('Content-Type', ctype);
      const buf = Buffer.from(await upstream.arrayBuffer());
      if (buf.length > MAX_BYTES) return res.status(413).end();
      res.end(buf);
      return;'''

if consumer_old in t:
    t = t.replace(consumer_old, consumer_new)

p.write_text(t)
print('  Swapped http.request for global fetch() (redirect-follow default)')
"
echo "Stage 3 complete."
