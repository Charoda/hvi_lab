#!/bin/bash
# Stage 1: Add upload preferences endpoint (FEAT-880)
# Creates:
#   - nodejs/express-multer/models/uploadPreference.js — Mongoose model
# Patches:
#   - nodejs/express-multer/index.js — add Mongoose connection + preference routes
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding upload preferences endpoint (FEAT-880)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# 1. Create models directory and UploadPreference model
mkdir -p nodejs/express-multer/models

cat > nodejs/express-multer/models/uploadPreference.js << 'EOF'
const mongoose = require('mongoose');

const uploadPreferenceSchema = new mongoose.Schema({
    userId: {
        type: String,
        required: true,
        unique: true,
    },
    preferences: {
        type: Object,
        default: {},
    },
}, { timestamps: true });

const UploadPreference = mongoose.model('UploadPreference', uploadPreferenceSchema);

module.exports = UploadPreference;
EOF

echo "  Created models/uploadPreference.js"

# 2. Add Mongoose connection and preference routes to index.js
python3 -c "
import sys

with open('$TARGET', 'r') as f:
    content = f.read()

original = content

# Add mongoose require after existing requires
old_requires = \"const fs = require('fs');\"
new_requires = \"\"\"const fs = require('fs');
const mongoose = require('mongoose');
const UploadPreference = require('./models/uploadPreference');\"\"\"

content = content.replace(old_requires, new_requires)

# Add MongoDB connection after FILE_PATH setup
old_path = \"fs.mkdirSync(FILE_PATH, { recursive: true });\"
new_path = \"\"\"fs.mkdirSync(FILE_PATH, { recursive: true });

// ---------- MongoDB Connection ----------
const MONGODB_URL = process.env.MONGODB_URL || 'mongodb://localhost:27017/file-uploads';
mongoose.connect(MONGODB_URL).then(() => {
    console.log('Connected to MongoDB');
}).catch((err) => {
    console.error('MongoDB connection error:', err.message);
});\"\"\"

content = content.replace(old_path, new_path)

# Add preference routes before the health endpoint
old_health = \"app.get('/', (req, res) => {\"
new_routes = \"\"\"// ---------- Upload Preferences API ----------

// FEAT-880: Get upload preferences
app.get('/api/upload-preferences/:userId', async (req, res) => {
    try {
        const doc = await UploadPreference.findOne({ userId: req.params.userId });
        res.json(doc ? doc.preferences : {});
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// FEAT-880: Update upload preferences (shallow merge)
app.patch('/api/upload-preferences/:userId', async (req, res) => {
    try {
        let doc = await UploadPreference.findOne({ userId: req.params.userId });
        if (!doc) {
            doc = new UploadPreference({ userId: req.params.userId, preferences: {} });
        }
        const merged = Object.assign({}, doc.preferences || {}, req.body);
        doc.preferences = merged;
        doc.markModified('preferences');
        await doc.save();
        res.json(doc.preferences);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/', (req, res) => {\"\"\"

content = content.replace(old_health, new_routes)

if content == original:
    print('ERROR: Could not patch index.js for preferences', file=sys.stderr)
    sys.exit(1)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added Mongoose connection + preference routes to index.js')
"

echo "Stage 1 complete."
