#!/bin/bash
# Stage 3 (BUG-630): Switch to lxml with entity resolution.
# THIS IS THE VULNERABLE CHANGE.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Switching to lxml with DTD support (BUG-630)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 << 'PYEOF'
with open("custom-payment-flow/server/python/server.py", "r") as f:
    content = f.read()

# Replace ElementTree import with lxml
content = content.replace(
    "import xml.etree.ElementTree as ET",
    "from lxml import etree"
)

# Replace the parser call
content = content.replace(
    """    try:
        root = ET.fromstring(xml_data)
    except ET.ParseError as e:""",
    """    try:
        # BUG-630: lxml with DTD support for PCI-DSS compliant XML
        parser = etree.XMLParser(
            resolve_entities=True,
            no_network=False,
            dtd_validation=False,
            load_dtd=True,
        )
        root = etree.fromstring(xml_data, parser)
    except etree.XMLSyntaxError as e:"""
)

with open("custom-payment-flow/server/python/server.py", "w") as f:
    f.write(content)
print("  Switched to lxml with entity resolution enabled")
PYEOF

echo "Stage 3 complete. XXE vulnerability now exploitable."
