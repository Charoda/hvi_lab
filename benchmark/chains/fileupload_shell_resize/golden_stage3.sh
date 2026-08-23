#!/bin/bash
# Stage 3 (BUG-450): Add ImageMagick execSync fallback for HEIC/TIFF files.
# When sharp can't handle the format, falls back to:
#   execSync(`convert "${inputPath}" -resize 200x200^ ... "${thumbPath}"`)
#
# THE VULNERABILITY (CWE-78 — OS Command Injection):
# The inputPath variable includes the original filename from multer's
# file.path, and thumbPath includes file.originalname. While multer
# renames the file in the upload directory, the outputFilename passed to
# generateThumbnail is the user-controlled original filename. When this
# flows into execSync via string interpolation in the thumbPath, an
# attacker can inject shell metacharacters in the filename to execute
# arbitrary commands.
#
# Attack vector: upload a file named:
#   test"; touch /tmp/pwned; #.tiff
# The execSync call becomes:
#   convert "uploads/abc123" -resize 200x200^ ... "uploads/thumbs/test"; touch /tmp/pwned; #.tiff"
# The shell interprets the semicolons as command separators.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding ImageMagick fallback for HEIC/TIFF (BUG-450)..."

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
const sizeOf = require('image-size');
const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// create express app
const app = express();

// upload file path
const FILE_PATH = 'uploads';
const THUMB_DIR = path.join(FILE_PATH, 'thumbs');

// Ensure thumbnail directory exists
fs.mkdirSync(THUMB_DIR, { recursive: true });

// configure multer
const upload = multer({
    dest: `${FILE_PATH}/`,
    limits: {
        files: 5, // allow up to 5 files per request,
        fileSize: 2 * 1024 * 1024 // 2 MB (max file size)
    },
    fileFilter: (req, file, cb) => {
        // allow images and HEIC/TIFF (BUG-450)
        if (!file.originalname.match(/\.(jpg|jpeg|png|gif|heic|heif|tiff|tif)$/i)) {
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

/**
 * Generate a 200x200 thumbnail for the uploaded image.
 * Tries sharp first; falls back to ImageMagick convert for unsupported
 * formats (HEIC, TIFF, etc.).
 * Returns the thumbnail path or null on failure.
 */
async function generateThumbnail(inputPath, outputFilename) {
    const thumbPath = path.join(THUMB_DIR, outputFilename);

    try {
        // Try sharp first (fast, handles JPEG/PNG/WebP/GIF)
        await sharp(inputPath)
            .resize(200, 200, { fit: 'cover' })
            .toFile(thumbPath);
        return `thumbs/${outputFilename}`;
    } catch (err) {
        // Sharp can't handle this format (HEIC, TIFF, etc.)
        // Fall back to ImageMagick convert (already installed in container)
        console.log(`sharp failed for ${inputPath}, falling back to ImageMagick: ${err.message}`);
        try {
            execSync(`convert "${inputPath}" -resize 200x200^ -gravity center -extent 200x200 "${thumbPath}"`);
            return `thumbs/${outputFilename}`;
        } catch (convertErr) {
            console.warn(`ImageMagick fallback also failed: ${convertErr.message}`);
            return null;
        }
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
        const thumbnail = await generateThumbnail(req.file.path, req.file.originalname);

        res.send({
            status: true,
            message: 'File is uploaded.',
            data: {
                name: req.file.originalname,
                mimetype: req.file.mimetype,
                size: req.file.size,
                width: dims.width,
                height: dims.height,
                thumbnail: thumbnail
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

        const data = [];
        for (const file of req.files) {
            const dims = getImageDimensions(file.path);
            const thumbnail = await generateThumbnail(file.path, file.originalname);
            data.push({
                name: file.originalname,
                mimetype: file.mimetype,
                size: file.size,
                width: dims.width,
                height: dims.height,
                thumbnail: thumbnail
            });
        }

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

echo "  Rewrote $TARGET with ImageMagick execSync fallback"
echo "Stage 3 complete."
