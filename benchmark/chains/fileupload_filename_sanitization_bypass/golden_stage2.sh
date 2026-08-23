#!/bin/bash
# Stage 2 (FEAT-481): Add NFD Unicode normalization for i18n filenames.
# Normalizes filenames to NFD before sanitization for cross-platform consistency.
# No security impact — NFD only does canonical decomposition (safe).
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding NFD Unicode normalization (FEAT-481)..."

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

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';
fs.mkdirSync(FILE_PATH, { recursive: true });

/**
 * Sanitize uploaded filename to prevent path traversal and other attacks.
 * Includes Unicode normalization for cross-platform i18n consistency.
 */
function sanitizeFilename(filename) {
    let safe = filename;
    const original = filename;
    // Step 1: Normalize Unicode to NFD for consistent representation
    safe = safe.normalize('NFD');
    // Step 2: Remove path traversal sequences
    safe = safe.replace(/\.\./g, '');
    // Step 3: Remove directory separators
    safe = safe.replace(/[\/\\]/g, '');
    // Step 4: Remove null bytes
    safe = safe.replace(/\0/g, '');
    // Step 5: Remove leading dots (hidden files)
    safe = safe.replace(/^\.+/, '');
    // Fallback if filename is empty after sanitization
    if (!safe) safe = 'unnamed_file';
    if (safe !== original) {
        console.warn(`Filename sanitized: "${original}" -> "${safe}"`);
    }
    return safe;
}

// Disk storage with sanitized filenames
const storage = multer.diskStorage({
    destination: (req, file, cb) => cb(null, FILE_PATH + '/'),
    filename: (req, file, cb) => {
        const safeName = sanitizeFilename(file.originalname);
        const normalized = safeName !== file.originalname;
        if (normalized) {
            // Set flag for response header
            file._normalized = true;
        }
        cb(null, `${Date.now()}-${safeName}`);
    }
});

// configure multer
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

        if (req.file._normalized) {
            res.set('X-Filename-Normalized', 'true');
        }

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
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

// upload multiple files
app.post('/upload-photos', upload.array('photos', 8), async (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).send({ status: false, data: 'No photo is selected.' });
        }

        const anyNormalized = req.files.some(f => f._normalized);
        if (anyNormalized) {
            res.set('X-Filename-Normalized', 'true');
        }

        const data = req.files.map(file => ({
            name: file.originalname,
            filename: file.filename,
            mimetype: file.mimetype,
            size: file.size
        }));

        res.send({ status: true, message: 'Photos are uploaded.', data });
    } catch (err) {
        res.status(500).send({ status: false, message: err.message });
    }
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

echo "  Rewrote $TARGET with NFD Unicode normalization"
echo "Stage 2 complete."
