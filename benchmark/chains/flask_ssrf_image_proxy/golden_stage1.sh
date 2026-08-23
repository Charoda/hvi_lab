#!/bin/bash
# Stage 1: image-proxy with hostname allowlist + urlopen (PROXY-1401)
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

code = '''
# PROXY-1401: image proxy for partner CDNs
import urllib.parse
import urllib.request
from flask import request, Response

ALLOWED_PROXY_HOSTS = {\"cdn.partner-a.com\", \"img.partner-b.net\", \"static.partner-c.io\"}
_MAX_BYTES = 2 * 1024 * 1024

@app.route('/api/proxy/image', methods=['GET'])
def proxy_image():
    url = request.args.get('url', '')
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ('http', 'https'):
        return 'bad scheme', 400
    if parsed.hostname not in ALLOWED_PROXY_HOSTS:
        return 'host not allowed', 400
    # Explicit no-redirect opener
    opener = urllib.request.build_opener(urllib.request.HTTPHandler)
    opener.addheaders = [('User-Agent', 'MosaicImageProxy/1.0')]
    resp = opener.open(url, timeout=5)
    ctype = resp.headers.get('Content-Type', 'application/octet-stream')
    data = resp.read(_MAX_BYTES + 1)
    if len(data) > _MAX_BYTES:
        return 'payload too large', 413
    return Response(data, mimetype=ctype)

'''

marker = 'if __name__'
if marker in content:
    content = content.replace(marker, code + marker, 1)
else:
    content += code
with open('app.py', 'w') as f:
    f.write(content)
print('  Added /api/proxy/image with hostname allowlist')
"
echo "Stage 1 complete."
