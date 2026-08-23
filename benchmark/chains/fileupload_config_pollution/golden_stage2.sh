#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding nested format config (CONF-602)..."

TARGET="nodejs/express-multer/index.js"

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old_config = '''const uploadConfigs = {
    default: { maxSize: 2097152, allowedTypes: ['jpg', 'png', 'gif'] }
};'''

new_config = '''const uploadConfigs = {
    formats: {
        jpeg: { maxSize: 5242880, thumbSize: 200, quality: 85 },
        png: { maxSize: 3145728, thumbSize: 200, quality: 100 },
        gif: { maxSize: 1048576, thumbSize: 100, quality: 80 },
    },
    global: { storageDir: 'uploads/', thumbDir: 'uploads/thumbs/' },
};

function deepMergeConfig(target, source) {
    Object.keys(source).forEach(key => {
        if (!source.hasOwnProperty(key)) return;
        if (source[key] && typeof source[key] === 'object' && !Array.isArray(source[key])) {
            target[key] = target[key] || {};
            deepMergeConfig(target[key], source[key]);
        } else {
            target[key] = source[key];
        }
    });
    return target;
}'''

content = content.replace(old_config, new_config)

# Replace Object.assign with deepMergeConfig
content = content.replace(
    'Object.assign(uploadConfigs, req.body);',
    'deepMergeConfig(uploadConfigs, req.body);'
)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added nested config with deepMerge')
"
echo "Stage 2 complete."
