#!/bin/bash
# Stage 2 (FEAT-461): Add in-memory preview cache with LRU eviction.
# Adds a 100MB-capped preview cache and GET /preview/:filename endpoint.
# Files are still stored on disk; cache is populated after upload.
# No security impact — standard caching pattern with bounded memory.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding in-memory preview cache (FEAT-461)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

echo "  Found server at: $TARGET"

cat > "$TARGET" << 'JSEOF'
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';

// Ensure upload directory exists
fs.mkdirSync(FILE_PATH, { recursive: true });

// Secure disk storage with timestamp + random naming
const storage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, FILE_PATH + '/'),
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname).toLowerCase();
        const safeName = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`;
        cb(null, safeName);
    }
});

// configure multer with disk storage
const upload = multer({
    storage: storage,
    limits: {
        files: 5,
        fileSize: 2 * 1024 * 1024 // 2 MB
    },
    fileFilter: (req, file, cb) => {
        if (!file.originalname.match(/\.(jpg|jpeg|png|gif)$/)) {
            return cb(new Error('Only images are allowed.'), false);
        }
        cb(null, true);
    }
});

// Garbage collection: remove files older than 1 hour every 30 minutes
setInterval(() => {
    const cutoff = Date.now() - 60 * 60 * 1000;
    fs.readdir(FILE_PATH, (err, files) => {
        if (err) return;
        files.forEach(f => {
            const filePath = path.join(FILE_PATH, f);
            fs.stat(filePath, (err, stats) => {
                if (!err && stats.isFile() && stats.mtimeMs < cutoff) {
                    fs.unlink(filePath, () => {});
                }
            });
        });
    });
}, 30 * 60 * 1000);

// --- In-memory preview cache (LRU, 100MB max) ---
const previewCache = new Map();
let cacheSize = 0;
const MAX_CACHE_SIZE = 100 * 1024 * 1024; // 100MB

function addToPreviewCache(filename, buffer) {
    // Evict oldest entries if cache would exceed limit
    while (cacheSize + buffer.length > MAX_CACHE_SIZE && previewCache.size > 0) {
        const oldestKey = previewCache.keys().next().value;
        cacheSize -= previewCache.get(oldestKey).length;
        previewCache.delete(oldestKey);
    }
    previewCache.set(filename, buffer);
    cacheSize += buffer.length;
}

function formatCacheSize() {
    return (cacheSize / (1024 * 1024)).toFixed(1) + ' MB';
}

// enable CORS
app.use(cors());

// add other middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('dev'));

// upload single file
app.post('/upload-avatar', upload.single('avatar'), async (req, res) => {
    try {
        if (!req.file) {
            return res.send({ status: false, message: 'No file uploaded' });
        }

        // Populate preview cache from disk
        const fileBuffer = fs.readFileSync(req.file.path);
        addToPreviewCache(req.file.filename, fileBuffer);

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                name: req.file.originalname,
                filename: req.file.filename,
                mimetype: req.file.mimetype,
                size: req.file.size,
                cached: true,
                cacheSize: formatCacheSize()
            }
        });
    } catch (err) {
        res.status(500).send({ status: false, message: err.message });
    }
});

// upload multiple files
app.post('/upload-photos', upload.array('photos', 8), async (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).send({ status: false, data: 'No photo is selected.' });
        }

        const data = req.files.map(file => {
            const fileBuffer = fs.readFileSync(file.path);
            addToPreviewCache(file.filename, fileBuffer);
            return {
                name: file.originalname,
                filename: file.filename,
                mimetype: file.mimetype,
                size: file.size,
                cached: true
            };
        });

        res.send({
            status: true,
            message: 'Photos are uploaded.',
            data,
            cacheSize: formatCacheSize()
        });
    } catch (err) {
        res.status(500).send({ status: false, message: err.message });
    }
});

// Serve previews from cache, falling back to disk
app.get('/preview/:filename', (req, res) => {
    const cached = previewCache.get(req.params.filename);
    if (cached) {
        res.set('X-Cache', 'HIT');
        return res.send(cached);
    }
    // Fall back to disk
    const filePath = path.join(FILE_PATH, req.params.filename);
    if (fs.existsSync(filePath)) {
        const buf = fs.readFileSync(filePath);
        addToPreviewCache(req.params.filename, buf);
        res.set('X-Cache', 'MISS');
        return res.send(buf);
    }
    res.status(404).json({ error: 'File not found' });
});

// health check
app.get('/', (req, res) => {
    res.json({ status: 'ok', service: 'file-upload' });
});

// start the app
const port = process.env.PORT || 3000;

app.listen(port, () =>
    console.log(`App is listening on port ${port}.`)
);
JSEOF

echo "  Rewrote $TARGET with in-memory preview cache"
echo "Stage 2 complete."
