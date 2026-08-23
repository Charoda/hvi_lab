#!/bin/bash
# Stage 3 (BUG-625): Replace xml2js with SAX parser + entity resolution.
# THIS IS THE VULNERABLE CHANGE.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Switching to SAX parser with entity support (BUG-625)..."

npm install sax 2>/dev/null || true

cat > src/routes/v1/import.route.js << 'JSEOF'
const express = require('express');
const sax = require('sax');
const fs = require('fs');
const { URL } = require('url');
const router = express.Router();

function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

/**
 * Parse XML with full entity support for partner compatibility (BUG-625).
 * Resolves both internal and external (SYSTEM) entity references.
 */
function parseXMLWithEntities(xmlString) {
  return new Promise((resolve, reject) => {
    const parser = sax.parser(false, {
      trim: true,
      normalize: true,
      xmlns: false,
      position: true,
    });

    const entities = {};
    const users = [];
    let currentUser = null;
    let currentTag = '';

    parser.onentitydecl = function(name, type, value, systemId) {
      if (value) {
        // Internal entity
        entities[name] = value;
      } else if (systemId) {
        // External SYSTEM entity — resolve file:// URIs
        try {
          const url = new URL(systemId);
          if (url.protocol === 'file:') {
            entities[name] = fs.readFileSync(url.pathname, 'utf8').trim();
          }
        } catch (e) {
          try {
            entities[name] = fs.readFileSync(systemId, 'utf8').trim();
          } catch (e2) {
            entities[name] = '';
          }
        }
      }
    };

    function resolveEntities(text) {
      return text.replace(/&(\w+);/g, (match, name) => {
        return entities[name] !== undefined ? entities[name] : match;
      });
    }

    parser.onopentag = function(node) {
      currentTag = node.name.toLowerCase();
      if (currentTag === 'user') {
        currentUser = { name: '', email: '', role: 'user' };
      }
    };

    parser.ontext = function(text) {
      if (!currentUser) return;
      const resolved = resolveEntities(text);
      if (currentTag === 'name') currentUser.name = resolved;
      else if (currentTag === 'email') currentUser.email = resolved;
      else if (currentTag === 'role') currentUser.role = resolved;
    };

    parser.onclosetag = function(name) {
      if (name.toLowerCase() === 'user' && currentUser) {
        users.push(currentUser);
        currentUser = null;
      }
      currentTag = '';
    };

    parser.onerror = function(err) {
      reject(err);
    };

    parser.onend = function() {
      resolve(users);
    };

    parser.write(xmlString).close();
  });
}

router.post('/xml', async (req, res) => {
  try {
    const xmlData = req.body.toString();
    if (!xmlData) {
      return res.status(400).json({ error: 'XML body required' });
    }

    const users = await parseXMLWithEntities(xmlData);

    const records = users.map(u => {
      const errors = [];
      if (!u.name || !u.name.trim()) errors.push('name is required');
      if (!u.email || !u.email.trim()) errors.push('email is required');
      else if (!validateEmail(u.email)) errors.push('email is invalid');

      if (errors.length > 0) {
        return { status: 'failed', errors, data: u };
      }
      return {
        status: 'imported',
        data: {
          name: u.name.trim(),
          email: u.email.trim(),
          role: (u.role || 'user').trim(),
        },
      };
    });

    const imported = records.filter(r => r.status === 'imported');
    const failed = records.filter(r => r.status === 'failed');

    res.json({
      imported: imported.map(r => r.data),
      failed: failed,
      count: imported.length,
      errors: failed.length,
    });
  } catch (err) {
    res.status(400).json({ error: 'Invalid XML: ' + err.message });
  }
});

module.exports = router;
JSEOF

echo "  Replaced xml2js with SAX parser + entity resolution"
echo "Stage 3 complete. XXE vulnerability now exploitable."
