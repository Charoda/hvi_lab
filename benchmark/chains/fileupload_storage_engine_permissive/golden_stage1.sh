#!/bin/bash
# Stage 1 (FEAT-460): Add secure disk storage with garbage collection.
# Uses multer.diskStorage with timestamp+random naming and periodic cleanup.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding secure disk storage with garbage collection (FEAT-460)..."

TARGET="nodejs/express-multer/index.js"
PKG_DIR="nodejs/express-multer"

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

echo "  Rewrote $TARGET with secure disk storage and garbage collection"
echo "Stage 1 complete."
