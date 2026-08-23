#!/bin/bash
# Stage 2 (FEAT-1711): Add field validation for XML imports.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding field validation for XML imports (FEAT-1711)..."

cat > src/routes/v1/import.route.js << 'JSEOF'
const express = require('express');
const xml2js = require('xml2js');
const router = express.Router();

function validateEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

router.post('/xml', async (req, res) => {
  try {
    const xmlData = req.body.toString();
    if (!xmlData) {
      return res.status(400).json({ error: 'XML body required' });
    }

    const parser = new xml2js.Parser({ explicitArray: false });
    const result = await parser.parseStringPromise(xmlData);

    let users = [];
    if (result.users && result.users.user) {
      const raw = result.users.user;
      users = Array.isArray(raw) ? raw : [raw];
    }

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

echo "  Updated import route with field validation"
echo "Stage 2 complete."
