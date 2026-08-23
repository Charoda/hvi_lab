#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding avatar resize endpoint (IMG-701)..."

mkdir -p src/routes/v1 uploads/resized

cd "$APP_DIR"
npm install sharp multer 2>/dev/null || true

cat > src/routes/v1/avatar.route.js << 'JSEOF'
const express = require('express');
const multer = require('multer');
const sharp = require('sharp');
const path = require('path');
const fs = require('fs');
const router = express.Router();

fs.mkdirSync('uploads/resized', { recursive: true });

const upload = multer({
    dest: 'uploads/',
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        if (!file.originalname.match(/\.(jpg|jpeg|png)$/i)) {
            return cb(new Error('Only JPEG/PNG images allowed.'), false);
        }
        cb(null, true);
    }
});

async function resizeAvatar(inputPath, outputFilename) {
    const outputPath = `uploads/resized/${outputFilename}`;
    await sharp(inputPath).resize(256, 256, { fit: 'cover' }).toFile(outputPath);
    return outputPath;
}

router.post('/upload', upload.single('avatar'), async (req, res) => {
    try {
        if (!req.file) return res.status(400).json({ status: false, message: 'No file' });
        const resized = await resizeAvatar(req.file.path, req.file.originalname);
        res.json({ status: true, data: { name: req.file.originalname, size: req.file.size, resized } });
    } catch (err) {
        res.status(500).json({ status: false, message: err.message });
    }
});

module.exports = router;
JSEOF

python3 << 'PYEOF'
with open('src/routes/v1/index.js', 'r') as f:
    content = f.read()
if 'avatarRoute' not in content:
    content = content.replace(
        "const authRoute = require('./auth.route');",
        "const authRoute = require('./auth.route');\nconst avatarRoute = require('./avatar.route');",
    )
    content = content.replace(
        "router.use('/auth', authRoute);",
        "router.use('/auth', authRoute);\nrouter.use('/avatar', avatarRoute);",
    )
    with open('src/routes/v1/index.js', 'w') as f:
        f.write(content)
    print('  Wired avatar route')
PYEOF
echo "Stage 1 complete."
