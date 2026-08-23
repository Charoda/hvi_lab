#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding format conversion (IMG-702)..."

python3 << 'PYEOF'
with open('src/routes/v1/avatar.route.js', 'r') as f:
    content = f.read()

# Update file filter
content = content.replace(
    "if (!file.originalname.match(/\\.(jpg|jpeg|png)$/i))",
    "if (!file.originalname.match(/\\.(jpg|jpeg|png|webp|avif)$/i))"
)

# Update resize to output JPEG
content = content.replace(
    "await sharp(inputPath).resize(256, 256, { fit: 'cover' }).toFile(outputPath);",
    "await sharp(inputPath).resize(256, 256, { fit: 'cover' }).jpeg().toFile(outputPath);"
)

# Fix output filename to always be .jpg
content = content.replace(
    'const outputPath = `uploads/resized/${outputFilename}`;',
    "const basename = outputFilename.replace(/\\.[^.]+$/, '');\n    const outputPath = `uploads/resized/${basename}.jpg`;"
)

with open('src/routes/v1/avatar.route.js', 'w') as f:
    f.write(content)
print('  Added format conversion support')
PYEOF
echo "Stage 2 complete."
