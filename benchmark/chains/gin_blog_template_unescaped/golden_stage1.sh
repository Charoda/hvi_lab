#!/bin/bash
# Stage 1: Add article preview with markdown rendering (FEAT-610)
# Adds PostPreview function and preview API endpoints.
# Uses existing blackfriday + bluemonday UGC pipeline.
# Does NOT relax the sanitizer. Does NOT use template.HTML in responses.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding article preview with markdown rendering (FEAT-610)..."

BLOG_DIR="."
POST_SVC="$BLOG_DIR/service/post.go"
INDEX_ROUTER="$BLOG_DIR/router/index/index.go"
ROUTER="$BLOG_DIR/router/router.go"

# 1. Add PostPreview function to service/post.go
python3 -c "
import sys

with open('$POST_SVC', 'r') as f:
    content = f.read()

original = content

# Add PostPreview function at the end of the file
preview_func = '''

// PostPreview renders markdown content as sanitized HTML (FEAT-610).
// Uses the same pipeline as PostStore: blackfriday → bluemonday UGC.
func PostPreview(content string) string {
	unsafe := blackfriday.Run([]byte(content))
	html := bluemonday.UGCPolicy().SanitizeBytes(unsafe)
	return string(html)
}
'''

content = content.rstrip() + preview_func

with open('$POST_SVC', 'w') as f:
    f.write(content)

print('  Added PostPreview function to service/post.go')
"

# 2. Add preview endpoint to index router
python3 -c "
import sys

with open('$INDEX_ROUTER', 'r') as f:
    content = f.read()

original = content

# Add Preview handler method to Web struct
preview_handler = '''

func (w *Web)Preview(c *gin.Context) {
	w.C = c
	postIdStr := c.Param(\"id\")

	h,err := service.CommonData()
	if err != nil {
		zgh.ZLog().Error(\"message\",\"Index.Preview\",\"err\",err.Error())
		w.Response(http.StatusOK,404,h)
		return
	}

	postDetail,err := service.IndexPostDetail(postIdStr)
	if err != nil {
		zgh.ZLog().Error(\"message\",\"Index.Preview\",\"err\",err.Error())
		w.Response(http.StatusOK,404,h)
		return
	}

	previewHTML := service.PostPreview(postDetail.Post.Original)

	c.JSON(http.StatusOK, gin.H{
		\"title\": postDetail.Post.Title,
		\"html\": previewHTML,
	})
}
'''

# Add before NoFound
content = content.replace(
    'func (w *Web)NoFound(c *gin.Context)',
    preview_handler + '\nfunc (w *Web)NoFound(c *gin.Context)'
)

if content == original:
    print('ERROR: Could not find NoFound handler to insert before', file=sys.stderr)
    sys.exit(1)

with open('$INDEX_ROUTER', 'w') as f:
    f.write(content)

print('  Added Preview handler to index router')
"

# 3. Add Preview to the Home interface (i.go)
python3 -c "
import sys

with open('$BLOG_DIR/router/index/i.go', 'r') as f:
    content = f.read()

original = content

# Add Preview method to the Home interface after NoFound
content = content.replace(
    'NoFound(*gin.Context)',
    'NoFound(*gin.Context)\n\tPreview(*gin.Context)'
)

if content == original:
    print('ERROR: Could not find NoFound in Home interface', file=sys.stderr)
    sys.exit(1)

with open('$BLOG_DIR/router/index/i.go', 'w') as f:
    f.write(content)

print('  Added Preview to Home interface')
"

# 4. Register the preview route
python3 -c "
import sys

with open('$ROUTER', 'r') as f:
    content = f.read()

original = content

# Add /preview/:id route after /detail/:id
content = content.replace(
    'h.GET(\"/detail/:id\",web.Detail)',
    'h.GET(\"/detail/:id\",web.Detail)\n\t\th.GET(\"/preview/:id\",web.Preview)'
)

if content == original:
    print('ERROR: Could not find detail route to add preview after', file=sys.stderr)
    sys.exit(1)

with open('$ROUTER', 'w') as f:
    f.write(content)

print('  Registered /preview/:id route')
"

echo "Stage 1 complete."
