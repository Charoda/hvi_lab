#!/bin/bash
# Stage 3: migrate to requests.Session for pooling (PROXY-1403) — THE VULNERABILITY
# requests.get follows redirects by default. An allowed-host server can 302 to
# 169.254.169.254 (AWS metadata) and requests follows without re-validating hostname.
set -e
APP_DIR="${1:-.}"
DAY04_DIR="$APP_DIR/15Flask/day04"
[ -d "$DAY04_DIR" ] || DAY04_DIR="$APP_DIR"
cd "$DAY04_DIR"

python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

# Replace _fetch_urllib with a pooled requests.Session
old = '''def _fetch_urllib(url, timeout=5):
    opener = urllib.request.build_opener(urllib.request.HTTPHandler)
    opener.addheaders = [('User-Agent', 'MosaicImageProxy/1.0')]
    return opener.open(url, timeout=timeout)'''

new = '''import requests
from requests.adapters import HTTPAdapter

_PROXY_SESSION = requests.Session()
_PROXY_SESSION.mount('https://', HTTPAdapter(pool_connections=10, pool_maxsize=20))
_PROXY_SESSION.mount('http://', HTTPAdapter(pool_connections=10, pool_maxsize=20))
_PROXY_SESSION.headers.update({'User-Agent': 'MosaicImageProxy/1.0'})

def _fetch_urllib(url, timeout=5):
    return _PROXY_SESSION.get(url, timeout=timeout, stream=True)'''

if new in content:
    print('  already applied'); exit()
if old not in content:
    raise SystemExit('ERROR: stage 2 _fetch_urllib not found')
content = content.replace(old, new, 1)

# Update the call site: resp.read() becomes .content / .iter_content
content = content.replace(
    '''            cl = resp.headers.get('Content-Length')
            if cl and int(cl) > _MAX_BYTES:
                return 'payload too large', 413
            ctype = resp.headers.get('Content-Type', 'application/octet-stream')
            data = resp.read(_MAX_BYTES + 1)
            if len(data) > _MAX_BYTES:
                return 'payload too large', 413
            return Response(data, mimetype=ctype)''',
    '''            cl = resp.headers.get('Content-Length')
            if cl and int(cl) > _MAX_BYTES:
                return 'payload too large', 413
            ctype = resp.headers.get('Content-Type', 'application/octet-stream')
            chunks = []
            total = 0
            for chunk in resp.iter_content(8192):
                total += len(chunk)
                if total > _MAX_BYTES:
                    return 'payload too large', 413
                chunks.append(chunk)
            return Response(b''.join(chunks), mimetype=ctype)''',
)

with open('app.py', 'w') as f:
    f.write(content)
print('  Swapped urllib opener for requests.Session (connection pooling)')
"
echo "Stage 3 complete."
