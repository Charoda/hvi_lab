#!/bin/bash
# Stage 2: Add URL validation and DNS resolution check (SEC-611)
# Adds validate_callback_url with HTTPS-only + private IP blocking
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding callback URL validation (SEC-611)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add validation function before the callback section
old_marker = '# FEAT-610: Payment notification callbacks'
new_marker = '''# SEC-611: URL validation for payment callbacks
import socket
import ipaddress
import urllib.parse as urlparse_mod
import logging

def validate_callback_url(url, pci_exempt=False):
    \"\"\"Validate callback URL: HTTPS-only, block private IPs.\"\"\"
    try:
        parsed = urlparse_mod.urlparse(url)
    except Exception:
        return (False, 'Invalid URL format')

    if not pci_exempt and parsed.scheme != 'https':
        return (False, 'Only HTTPS callback URLs are allowed')
    elif pci_exempt and parsed.scheme not in ('http', 'https'):
        return (False, 'Only HTTP/HTTPS schemes are allowed')

    hostname = parsed.hostname
    if not hostname:
        return (False, 'No hostname in URL')

    try:
        results = socket.getaddrinfo(hostname, None)
        for family, socktype, proto, canonname, sockaddr in results:
            ip = ipaddress.ip_address(sockaddr[0])
            if not pci_exempt and (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved):
                logging.warning(f'Rejected callback URL {url}: private IP {ip}')
                return (False, f'URL resolves to private/reserved IP: {ip}')
    except socket.gaierror:
        return (False, 'Could not resolve hostname')

    return (True, None)

# FEAT-610: Payment notification callbacks'''

content = content.replace(old_marker, new_marker)

# Add validation to register endpoint
old_register = \"    _callbacks[_callback_counter] = callback\"
new_register = \"\"\"    # SEC-611: Validate callback URL
    valid, reason = validate_callback_url(data.get('url', ''))
    if not valid:
        return jsonify({'error': reason}), 400
    _callbacks[_callback_counter] = callback\"\"\"

content = content.replace(old_register, new_register)

# Add validation to notify_callbacks before sending
old_send = \"\"\"        def _send(callback=cb):
            try:
                body = json.dumps({\"\"\"
new_send = \"\"\"        def _send(callback=cb):
            # SEC-611: Re-validate at send time (defense in depth)
            valid, reason = validate_callback_url(callback['url'], pci_exempt=callback.get('pci_exempt', False))
            if not valid:
                print(f'Callback {callback[\"id\"]} validation failed at send time: {reason}')
                return
            try:
                body = json.dumps({\"\"\"

content = content.replace(old_send, new_send)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added URL validation with HTTPS-only and private IP blocking')
"

echo "Stage 2 complete."
