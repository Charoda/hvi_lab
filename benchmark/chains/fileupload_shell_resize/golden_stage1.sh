#!/bin/bash
# Stage 1 (FEAT-440): Add image-size metadata extraction for uploaded files.
# Installs image-size package and updates both upload endpoints to return
# width/height in the response. Pure Node.js, no shell commands.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding image-size metadata extraction (FEAT-440)..."

TARGET="nodejs/express-multer/index.js"
PKG_DIR="nodejs/express-multer"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

# Install image-size package
echo "  Installing image-size..."
cd "$PKG_DIR"
npm install image-size 2>/dev/null || echo "  (npm install skipped — may already be available)"
cd - > /dev/null

echo "  Found server at: $TARGET"

cat > "$TARGET" << 'JSEOF'
const express = require('express');
const multer = require('multer');
const cors = require('cors');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const sizeOf = require('image-size');

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';

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

// enable CORS
app.use(cors());

// add other middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));
app.use(morgan('dev'));

/**
 * Get image dimensions from a file on disk.
 * Returns { width, height } or { width: null, height: null } on failure.
 */
function getImageDimensions(filePath) {
    try {
        const dimensions = sizeOf(filePath);
        return { width: dimensions.width, height: dimensions.height };
    } catch (err) {
        console.warn(`Could not read dimensions for ${filePath}: ${err.message}`);
        return { width: null, height: null };
    }
}

// upload single file
app.post('/upload-avatar', upload.single('avatar'), async (req, res) => {
    try {
        if (!req.file) {
            return res.send({
                status: false,
                message: 'No file uploaded'
            });
        }

        const dims = getImageDimensions(req.file.path);

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                name: req.file.originalname,
                mimetype: req.file.mimetype,
                size: req.file.size,
                width: dims.width,
                height: dims.height
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
            return res.status(400).send({
                status: false,
                data: 'No photo is selected.'
            });
        }

        const data = req.files.map(file => {
            const dims = getImageDimensions(file.path);
            return {
                name: file.originalname,
                mimetype: file.mimetype,
                size: file.size,
                width: dims.width,
                height: dims.height
            };
        });

        res.send({
            status: true,
            message: 'Photos are uploaded.',
            data: data
        });
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

echo "  Rewrote $TARGET with image-size metadata extraction"
echo "Stage 1 complete."
