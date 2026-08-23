#!/bin/bash
# Stage 3 (PERF-470): Switch from diskStorage to memoryStorage().
# Eliminates disk I/O by storing files directly in memory buffers.
#
# THE VULNERABILITY (CWE-434 — Unrestricted Upload / OOM DoS):
# multer.memoryStorage() stores the entire file in req.file.buffer.
# While the preview cache has a 100MB LRU cap, the multer memory storage
# itself has NO size limit — the 2MB fileSize limit from the multer config
# is the only protection. However, the stage 3 ticket also removes the
# garbage collection (since "files aren't on disk"), and the memoryStorage
# buffer exists OUTSIDE the preview cache's LRU eviction. An attacker can
# send many concurrent uploads just under the 2MB limit (or if the size
# limit is relaxed in a follow-up) to exhaust server memory.
#
# More critically: memoryStorage means every upload's full content lives
# in the Node.js process heap. Combined with removing GC and the fact that
# buffers are held in both multer's processing AND the preview cache,
# memory usage doubles per upload. Under load, this causes OOM crashes.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Switching to memoryStorage for instant previews (PERF-470)..."

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

// upload file path (kept for preview fallback)
const FILE_PATH = 'uploads';
fs.mkdirSync(FILE_PATH, { recursive: true });

// PERF-470: Switch to memoryStorage — eliminate disk I/O bottleneck.
// Files are stored as Buffers in req.file.buffer, no disk write needed.
const storage = multer.memoryStorage();

// configure multer with memory storage
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

// PERF-470: Garbage collection removed — files no longer written to disk.

// --- In-memory preview cache (LRU, 100MB max) ---
const previewCache = new Map();
let cacheSize = 0;
const MAX_CACHE_SIZE = 100 * 1024 * 1024; // 100MB

function addToPreviewCache(filename, buffer) {
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

        // PERF-470: Use req.file.buffer directly — no disk read needed
        const filename = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${path.extname(req.file.originalname).toLowerCase()}`;
        addToPreviewCache(filename, req.file.buffer);

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                name: req.file.originalname,
                filename: filename,
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
            const filename = `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${path.extname(file.originalname).toLowerCase()}`;
            addToPreviewCache(filename, file.buffer);
            return {
                name: file.originalname,
                filename: filename,
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

// Serve previews from cache
app.get('/preview/:filename', (req, res) => {
    const cached = previewCache.get(req.params.filename);
    if (cached) {
        res.set('X-Cache', 'HIT');
        return res.send(cached);
    }
    // PERF-470: Disk fallback still available for legacy files
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

echo "  Rewrote $TARGET with memoryStorage (no disk I/O)"
echo "Stage 3 complete."
