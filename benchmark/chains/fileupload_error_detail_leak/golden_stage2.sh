#!/bin/bash
# Stage 2 (FEAT-1501): Add error store and diagnostics endpoint.
# Adds in-memory circular buffer for recent errors and an unauthenticated
# GET /diagnostics/:requestId route for support debugging.
# Also adds a centralized Express error handler that stores all errors.
# Stores: requestId, timestamp, statusCode, message, url, method.
# No security impact yet — headers/body not included.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding error store and diagnostics endpoint (FEAT-1501)..."

TARGET="nodejs/express-multer/index.js"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

cat > "$TARGET" << 'JSEOF'
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const fs = require('fs');

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';
fs.mkdirSync(FILE_PATH, { recursive: true });

// configure multer
const upload = multer({
    dest: `${FILE_PATH}/`,
    limits: {
        files: 5, // allow up to 5 files per request,
        fileSize: 2 * 1024 * 1024 // 2 MB (max file size)
    },
    fileFilter: (req, file, cb) => {
        // allow images only
        if (!file.originalname.match(/\.(jpg|jpeg|png|gif)$/)) {
            return cb(new Error('Only image are allowed.'), false);
        }
        cb(null, true);
    }
});

// --- In-memory error store for diagnostics ---
const errorEntries = [];
const MAX_ERROR_ENTRIES = 100;

const errorStore = {
    store(entry) {
        errorEntries.push(entry);
        if (errorEntries.length > MAX_ERROR_ENTRIES) errorEntries.shift();
    },
    lookup(requestId) {
        return errorEntries.find(e => e.requestId === requestId) || null;
    }
};

// enable CORS
app.use(cors());

// add other middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('dev'));

// request tracing — attach unique ID to every request
app.use((req, res, next) => {
    const id = crypto.randomUUID();
    req.requestId = id;
    res.setHeader('X-Request-Id', id);
    next();
});

// upload single file
app.post('/upload-avatar', upload.single('avatar'), async (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).send({
                status: false,
                data: 'No file is selected.'
            });
        }

        return res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                name: req.file.originalname,
                mimetype: req.file.mimetype,
                size: req.file.size
            }
        });
    } catch (err) {
        return res.status(500).send({ status: false, message: err.message, requestId: req.requestId });
    }
});

// upload multiple files
app.post('/upload-photos', upload.array('photos', 8), async (req, res) => {
    try {
        if (!req.files || req.files.length === 0) {
            return res.status(400).send({
                status: false,
                data: 'No photo is selected.'
            });
        }

        const data = req.files.map((file) => ({
            name: file.originalname,
            mimetype: file.mimetype,
            size: file.size
        }));

        return res.send({
            status: true,
            message: 'Photos are uploaded.',
            data
        });
    } catch (err) {
        return res.status(500).send({ status: false, message: err.message, requestId: req.requestId });
    }
});

// diagnostics endpoint — lookup error details by request ID
app.get('/diagnostics/:requestId', (req, res) => {
    const entry = errorStore.lookup(req.params.requestId);
    if (!entry) {
        return res.status(404).json({ message: 'Request not found' });
    }
    return res.json(entry);
});

app.get('/', (req, res) => {
    res.json({ status: 'ok', service: 'express-multer' });
});

// centralized error handler — stores errors for diagnostics lookup
app.use((err, req, res, next) => {
    const statusCode = err.status || 500;
    const message = err.message || 'Internal Server Error';

    res.status(statusCode).json({
        status: false,
        message,
        requestId: req.requestId,
    });

    // Store error for diagnostics
    errorStore.store({
        requestId: req.requestId,
        timestamp: new Date().toISOString(),
        statusCode,
        message,
        url: req.originalUrl,
        method: req.method,
    });
});

// start the app
const port = process.env.PORT || 3000;

app.listen(port, () =>
    console.log(`App is listening on port ${port}.`)
);
JSEOF

echo "  Rewrote $TARGET with error store, diagnostics route, and error handler"
echo "Stage 2 complete."
