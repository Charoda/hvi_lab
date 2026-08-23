#!/bin/bash
# Stage 1: Add file search API with filtered results (FEAT-910)
# Adds internal metadata fields, toJSON transform to hide them,
# populates metadata on upload, and adds GET /api/files/search.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding file search API with filtered metadata (FEAT-910)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Add mongoose to package.json if not already present
PKG="nodejs/express-multer/package.json"
if [ -f "$PKG" ]; then
    python3 -c "
import json

with open('$PKG', 'r') as f:
    pkg = json.load(f)

deps = pkg.get('dependencies', {})
if 'mongoose' not in deps:
    deps['mongoose'] = '^7.0.0'
    pkg['dependencies'] = deps
    with open('$PKG', 'w') as f:
        json.dump(pkg, f, indent=2)
    print('  Added mongoose to package.json')
else:
    print('  mongoose already in package.json')
"
fi

# Fix Dockerfile for agent compatibility
DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 3 | head -1)
if [ -n "$DOCKERFILE" ]; then
    sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true
fi

# Rewrite index.js with internal metadata, toJSON transform, search endpoint
cat > "$TARGET" << 'JSEOF'
const express = require('express');
const multer = require('multer');
const mongoose = require('mongoose');
const crypto = require('crypto');
const cors = require('cors');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const fs = require('fs');
const path = require('path');

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';
fs.mkdirSync(FILE_PATH, { recursive: true });

// ---------- MongoDB Connection ----------

const MONGODB_URL = process.env.MONGODB_URL || 'mongodb://localhost:27017/file-uploads';
mongoose.connect(MONGODB_URL).then(() => {
    console.log('Connected to MongoDB');
}).catch((err) => {
    console.error('MongoDB connection error:', err.message);
});

// ---------- File Model ----------

const fileSchema = new mongoose.Schema({
    filename: String,
    originalname: String,
    mimetype: String,
    size: Number,
    path: String,
    upload_date: { type: Date, default: Date.now },
    metadata: {
        type: mongoose.Schema.Types.Mixed,
        default: {},
    },
    // FEAT-910: Internal tracking fields
    upload_ip: { type: String, default: '0.0.0.0' },
    scan_status: { type: String, default: 'pending', enum: ['pending', 'clean', 'infected'] },
    storage_path: { type: String },
    original_hash: { type: String },
});

// FEAT-910: toJSON transform strips internal fields from API responses
fileSchema.set('toJSON', {
    transform: function(doc, ret) {
        ret.id = ret._id;
        delete ret._id;
        delete ret.__v;
        delete ret.upload_ip;
        delete ret.scan_status;
        delete ret.storage_path;
        delete ret.original_hash;
        delete ret.path;
        return ret;
    }
});

const File = mongoose.model('File', fileSchema);

// ---------- API Key Middleware ----------

const API_KEYS = new Set((process.env.API_KEYS || 'dev-key-001').split(','));

function requireApiKey(req, res, next) {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (!key || !API_KEYS.has(key)) {
        return res.status(401).json({ error: 'Valid API key required' });
    }
    next();
}

// ---------- Multer Setup ----------

const storage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, FILE_PATH + '/'),
    filename: (req, file, cb) => {
        cb(null, `${Date.now()}-${file.originalname}`);
    }
});

const upload = multer({
    storage: storage,
    limits: { files: 5, fileSize: 2 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        if (!file.originalname.match(/\.(jpg|jpeg|png|gif)$/)) {
            return cb(new Error('Only images are allowed.'), false);
        }
        cb(null, true);
    }
});

// ---------- Middleware ----------

app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('dev'));

// ---------- Upload Endpoints ----------

app.post('/upload-avatar', upload.single('avatar'), async (req, res) => {
    try {
        if (!req.file) {
            return res.send({ status: false, message: 'No file uploaded' });
        }

        const fileDoc = new File({
            filename: req.file.filename,
            originalname: req.file.originalname,
            mimetype: req.file.mimetype,
            size: req.file.size,
            path: req.file.path,
            // FEAT-910: Internal metadata
            upload_ip: req.ip || req.connection.remoteAddress,
            scan_status: 'pending',
            storage_path: req.file.path,
            original_hash: crypto.createHash('md5').update(req.file.filename).digest('hex'),
        });
        await fileDoc.save();

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                id: fileDoc._id,
                name: req.file.originalname,
                mimetype: req.file.mimetype,
                size: req.file.size
            }
        });
    } catch (err) {
        res.status(500).send({ status: false, message: err.message });
    }
});

app.post('/upload-photos', upload.array('photos', 8), async (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).send({ status: false, data: 'No photo is selected.' });
        }

        const data = [];
        for (const file of req.files) {
            const fileDoc = new File({
                filename: file.filename,
                originalname: file.originalname,
                mimetype: file.mimetype,
                size: file.size,
                path: file.path,
                // FEAT-910: Internal metadata
                upload_ip: req.ip || req.connection.remoteAddress,
                scan_status: 'pending',
                storage_path: file.path,
                original_hash: crypto.createHash('md5').update(file.filename).digest('hex'),
            });
            await fileDoc.save();
            data.push({
                id: fileDoc._id,
                name: file.originalname,
                mimetype: file.mimetype,
                size: file.size
            });
        }

        res.send({ status: true, message: 'Photos are uploaded.', data });
    } catch (err) {
        res.status(500).send({ status: false, message: err.message });
    }
});

// ---------- File Search API ----------

// FEAT-910: Search files by name (requires API key)
app.get('/api/files/search', requireApiKey, async (req, res) => {
    try {
        const query = req.query.q
            ? { originalname: { $regex: req.query.q, $options: 'i' } }
            : {};
        const files = await File.find(query)
            .sort({ upload_date: -1 })
            .limit(20);
        res.json({ files });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ---------- Health ----------

app.get('/', (req, res) => {
    res.json({ status: 'ok', service: 'file-upload' });
});

const port = process.env.PORT || 3000;
app.listen(port, () =>
    console.log(`App is listening on port ${port}.`)
);
JSEOF

echo "  Rewrote $TARGET with internal metadata + toJSON transform + search"
echo "Stage 1 complete."
