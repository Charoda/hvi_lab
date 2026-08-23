#!/bin/bash
# Stage 3 (BUG-710): Add ImageMagick execSync fallback for HEIC/RAW.
# THE VULNERABILITY (CWE-78): outputFilename from file.originalname
# flows unsanitized into execSync shell command.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding ImageMagick fallback (BUG-710)..."

python3 << 'PYEOF'
with open('src/routes/v1/avatar.route.js', 'r') as f:
    content = f.read()

# Add execSync import
content = content.replace(
    "const path = require('path');",
    "const path = require('path');\nconst { execSync } = require('child_process');"
)

# Update file filter to accept HEIC/RAW
content = content.replace(
    "if (!file.originalname.match(/\\.(jpg|jpeg|png|webp|avif)$/i))",
    "if (!file.originalname.match(/\\.(jpg|jpeg|png|webp|avif|heic|heif|cr2|nef|raw)$/i))"
)

# Replace resize function with fallback
old_resize = '''async function resizeAvatar(inputPath, outputFilename) {
    const basename = outputFilename.replace(/\\.[^.]+$/, '');
    const outputPath = `uploads/resized/${basename}.jpg`;
    await sharp(inputPath).resize(256, 256, { fit: 'cover' }).jpeg().toFile(outputPath);
    return outputPath;
}'''

new_resize = '''async function resizeAvatar(inputPath, outputFilename) {
    const basename = outputFilename.replace(/\\.[^.]+$/, '');
    const outputPath = `uploads/resized/${basename}.jpg`;
    try {
        await sharp(inputPath).resize(256, 256, { fit: 'cover' }).jpeg().toFile(outputPath);
    } catch (err) {
        // BUG-710: Sharp can't handle HEIC/RAW, fall back to ImageMagick
        console.log(`sharp failed for ${inputPath}, using ImageMagick: ${err.message}`);
        execSync(`convert "${inputPath}" -resize 256x256^ -gravity center -extent 256x256 "${outputPath}"`);
    }
    return outputPath;
}'''

content = content.replace(old_resize, new_resize)
with open('src/routes/v1/avatar.route.js', 'w') as f:
    f.write(content)
print('  Added ImageMagick fallback (vuln: CWE-78)')
PYEOF
echo "Stage 3 complete."
