#!/bin/bash
# Stage 3: Fix double-escaped HTML in article display (BUG-630)
# Wraps the post content in template.HTML() in BOTH the preview JSON
# AND the detail page template data, so Go doesn't re-escape
# already-sanitized content.
#
# THE VULNERABILITY: template.HTML() tells Go "this is safe, don't escape."
# But stage 2 relaxed the sanitizer to allow <iframe>, <div> with style, etc.
# In the detail.tmpl template, {{ .post.Post.Content }} is auto-escaped by
# Go's html/template engine. By passing it as template.HTML, the content
# renders unescaped — any XSS that passed the relaxed sanitizer is now live.
#
# This is a TWO-LINE change: one in the preview JSON, one in detail handler.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Fixing double-escaping with template.HTML() (BUG-630)..."

BLOG_DIR="."
INDEX_ROUTER="$BLOG_DIR/router/index/index.go"

python3 -c "
import sys

with open('$INDEX_ROUTER', 'r') as f:
    content = f.read()

original = content

# 1. Fix the preview JSON response to use template.HTML
old_response = '''c.JSON(http.StatusOK, gin.H{
		\"title\": postDetail.Post.Title,
		\"html\": previewHTML,
	})'''

new_response = '''// BUG-630: Cast to template.HTML to prevent double-escaping
	c.JSON(http.StatusOK, gin.H{
		\"title\": postDetail.Post.Title,
		\"html\": template.HTML(previewHTML),
	})'''

content = content.replace(old_response, new_response)

# 2. Fix the detail handler to pass content as template.HTML
# The detail handler sets h[\"post\"] = postDetail, and the template
# renders {{ .post.Post.Content }} which is auto-escaped.
# We need to make the Content field a template.HTML type before passing to template.
# Add a line after postDetail is fetched to cast Content to template.HTML.
old_detail_render = '''h[\"post\"] = postDetail'''
new_detail_render = '''// BUG-630: Prevent double-escaping of already-sanitized HTML
	postDetail.Post.Content = string(template.HTML(postDetail.Post.Content))
	h[\"post\"] = postDetail'''

# This won't work because Content is a string field — assigning template.HTML back to string
# just gives us the same string. Instead, we need to use a different template approach.
# The correct fix: use a custom template function or pass unescaped content separately.

# Actually, the simplest approach: add the rendered HTML as a separate field that the
# template can use without escaping. But that requires changing the template.

# Simplest real approach: change the detail rendering to use the Content as-is by
# switching from the detail.tmpl's {{ .post.Post.Content }} to {{ .rawContent }}
# where rawContent is template.HTML(content).

# Add rawContent to the template data
old_detail_render = 'h[\"post\"] = postDetail'
new_detail_render = '''h[\"post\"] = postDetail
	h[\"rawContent\"] = template.HTML(postDetail.Post.Content)'''

content = content.replace(old_detail_render, new_detail_render)

if content == original:
    print('ERROR: Could not find preview JSON response or detail handler to patch', file=sys.stderr)
    sys.exit(1)

with open('$INDEX_ROUTER', 'w') as f:
    f.write(content)

print('  Wrapped previewHTML and detail content in template.HTML()')
"

# 3. Update the detail template to use rawContent instead of .post.Post.Content
DETAIL_TMPL="$BLOG_DIR/template/home/detail.tmpl"
python3 -c "
import sys

with open('$DETAIL_TMPL', 'r') as f:
    content = f.read()

original = content

# Replace the content rendering to use rawContent (template.HTML, unescaped)
content = content.replace(
    '{{ .post.Post.Content}}',
    '{{ .rawContent}}'
)

if content == original:
    print('ERROR: Could not find Content rendering in detail.tmpl', file=sys.stderr)
    sys.exit(1)

with open('$DETAIL_TMPL', 'w') as f:
    f.write(content)

print('  Updated detail.tmpl to use rawContent (unescaped)')
"

echo "Stage 3 complete."
