#!/bin/bash
# Stage 1: Add Mongoose File model with tags field + GET endpoint (FEAT-900)
# Adds mongoose dependency, File model with Schema.Types.Mixed tags,
# persists uploads to MongoDB, and GET /api/files/:id/tags endpoint.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding Mongoose File model with tags field (FEAT-900)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Add mongoose to package.json
PKG="nodejs/express-multer/package.json"
if [ -f "$PKG" ]; then
    python3 -c "
import json, sys

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

# Rewrite index.js with Mongoose integration
cat > "$TARGET" << 'JSEOF'
const express = require('express');
const multer = require('multer');
const mongoose = require('mongoose');
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
    tags: {
        type: mongoose.Schema.Types.Mixed,
        default: {},
    },
});

const File = mongoose.model('File', fileSchema);

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
        });
        await fileDoc.save();

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                id: fileDoc._id,
                name: req.file.originalname,
                filename: req.file.filename,
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
            });
            await fileDoc.save();
            data.push({
                id: fileDoc._id,
                name: file.originalname,
                filename: file.filename,
                mimetype: file.mimetype,
                size: file.size
            });
        }

        res.send({ status: true, message: 'Photos are uploaded.', data });
    } catch (err) {
        res.status(500).send({ status: false, message: err.message });
    }
});

// ---------- File Tags API ----------

// FEAT-900: Get file tags
app.get('/api/files/:id/tags', async (req, res) => {
    try {
        const file = await File.findById(req.params.id);
        if (!file) {
            return res.status(404).json({ error: 'File not found' });
        }
        res.json(file.tags || {});
    } catch (err) {
        res.status(400).json({ error: 'Invalid file ID' });
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

echo "  Rewrote $TARGET with Mongoose File model + tags field"
echo "Stage 1 complete."
