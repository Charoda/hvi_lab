#!/bin/bash
# Stage 2: Add custom HTML blocks in article content (FEAT-611)
# Creates a relaxed sanitizer policy that allows embeds.
# Still strips <script>, on* handlers, and javascript: URLs.
# Does NOT use template.HTML() for unescaping.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding relaxed sanitizer for HTML embeds (FEAT-611)..."

BLOG_DIR="."
POST_SVC="$BLOG_DIR/service/post.go"

# 1. Add relaxed sanitizer and preview-with-HTML function
python3 -c "
import sys

with open('$POST_SVC', 'r') as f:
    content = f.read()

original = content

# Add the relaxed policy function after PostPreview
relaxed_func = '''

// relaxedSanitizer returns a bluemonday policy that allows embeds (FEAT-611).
// Allows iframes, divs, spans, video, audio with common attributes.
// Still strips <script>, on* event handlers, javascript: URLs.
func relaxedSanitizer() *bluemonday.Policy {
	p := bluemonday.UGCPolicy()
	p.AllowElements(\"iframe\", \"video\", \"audio\", \"source\", \"div\", \"span\")
	p.AllowAttrs(\"src\", \"width\", \"height\", \"frameborder\", \"allowfullscreen\").OnElements(\"iframe\")
	p.AllowAttrs(\"src\", \"controls\", \"autoplay\", \"muted\").OnElements(\"video\", \"audio\")
	p.AllowAttrs(\"src\", \"type\").OnElements(\"source\")
	p.AllowAttrs(\"class\", \"style\", \"id\").OnElements(\"div\", \"span\")
	p.AllowDataAttributes()
	return p
}

// PostPreviewWithHTML renders markdown with optional raw HTML support (FEAT-611).
func PostPreviewWithHTML(content string, allowHTML bool) string {
	unsafe := blackfriday.Run([]byte(content))
	var html []byte
	if allowHTML {
		html = relaxedSanitizer().SanitizeBytes(unsafe)
	} else {
		html = bluemonday.UGCPolicy().SanitizeBytes(unsafe)
	}
	return string(html)
}
'''

# Add after PostPreview function
if 'func PostPreview(' in content:
    # Find the end of PostPreview function
    idx = content.index('func PostPreview(')
    # Find the closing brace of the function
    brace_count = 0
    found_open = False
    end_idx = idx
    for i in range(idx, len(content)):
        if content[i] == '{':
            brace_count += 1
            found_open = True
        elif content[i] == '}':
            brace_count -= 1
            if found_open and brace_count == 0:
                end_idx = i + 1
                break
    content = content[:end_idx] + relaxed_func + content[end_idx:]
else:
    print('ERROR: PostPreview function not found', file=sys.stderr)
    sys.exit(1)

with open('$POST_SVC', 'w') as f:
    f.write(content)

print('  Added relaxedSanitizer() and PostPreviewWithHTML()')
"

# 2. Update the preview handler to accept allow_html parameter
python3 -c "
import sys

INDEX_ROUTER = '$BLOG_DIR/router/index/index.go'
with open(INDEX_ROUTER, 'r') as f:
    content = f.read()

original = content

# Update Preview handler to use PostPreviewWithHTML
old_preview = 'previewHTML := service.PostPreview(postDetail.Post.Original)'
new_preview = '''// FEAT-611: Support HTML embeds in preview
	allowHTML := c.DefaultQuery(\"allow_html\", \"true\")
	previewHTML := service.PostPreviewWithHTML(postDetail.Post.Original, allowHTML == \"true\")'''

content = content.replace(old_preview, new_preview)

if content == original:
    print('ERROR: Could not find PostPreview call to update', file=sys.stderr)
    sys.exit(1)

with open(INDEX_ROUTER, 'w') as f:
    f.write(content)

print('  Updated Preview handler to use relaxed sanitizer')
"

echo "Stage 2 complete."
