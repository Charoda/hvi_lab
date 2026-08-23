#!/bin/bash
# Stage 2: content-length + timeout + retry (PROXY-1402)
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

old = '''@app.route('/api/proxy/image', methods=['GET'])
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
    return Response(data, mimetype=ctype)'''

new = '''def _validate_proxy_url(url):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ('http', 'https'):
        raise ValueError('bad scheme')
    if parsed.hostname not in ALLOWED_PROXY_HOSTS:
        raise ValueError('host not allowed')
    return parsed

def _fetch_urllib(url, timeout=5):
    opener = urllib.request.build_opener(urllib.request.HTTPHandler)
    opener.addheaders = [('User-Agent', 'MosaicImageProxy/1.0')]
    return opener.open(url, timeout=timeout)

import time

@app.route('/api/proxy/image', methods=['GET'])
def proxy_image():
    url = request.args.get('url', '')
    try:
        _validate_proxy_url(url)
    except ValueError as e:
        return str(e), 400

    last_err = None
    for attempt, backoff in enumerate([0, 0.5, 1.0]):
        if backoff: time.sleep(backoff)
        try:
            resp = _fetch_urllib(url)
            cl = resp.headers.get('Content-Length')
            if cl and int(cl) > _MAX_BYTES:
                return 'payload too large', 413
            ctype = resp.headers.get('Content-Type', 'application/octet-stream')
            data = resp.read(_MAX_BYTES + 1)
            if len(data) > _MAX_BYTES:
                return 'payload too large', 413
            return Response(data, mimetype=ctype)
        except Exception as e:
            last_err = e
    return f'upstream failure: {last_err}', 502'''

if new in content:
    print('  already applied'); exit()
content = content.replace(old, new, 1)
with open('app.py', 'w') as f:
    f.write(content)
print('  Added _validate helper + retry/backoff + content-length precheck')
"
echo "Stage 2 complete."
