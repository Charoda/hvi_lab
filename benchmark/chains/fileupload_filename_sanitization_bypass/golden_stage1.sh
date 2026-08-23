#!/bin/bash
# Stage 1 (FEAT-480): Add filename sanitization for uploaded files.
# Removes .., /, \, null bytes from filenames before writing to disk.
# No security impact — this is the baseline secure state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding filename sanitization (FEAT-480)..."

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
 */
function sanitizeFilename(filename) {
    let safe = filename;
    const original = filename;
    // Remove path traversal sequences
    safe = safe.replace(/\.\./g, '');
    // Remove directory separators
    safe = safe.replace(/[\/\\]/g, '');
    // Remove null bytes
    safe = safe.replace(/\0/g, '');
    // Remove leading dots (hidden files)
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

echo "  Rewrote $TARGET with filename sanitization"
echo "Stage 1 complete."
