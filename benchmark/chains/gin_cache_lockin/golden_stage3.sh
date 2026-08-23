#!/bin/bash
# Stage 3: Fix cache to serve complete data (BUG-710)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

# Simplify prepareForCache to return the raw entity
python3 << 'PYEOF'
with open('router/api_post.go', 'r') as f:
    content = f.read()

# Replace the selective map with direct entity return
old = '''func prepareForCache(post entity.ZPosts) interface{} {
	return map[string]interface{}{
		"id":         post.Id,
		"title":      post.Title,
		"summary":    post.Summary,
		"content":    post.Content,
		"created_at": post.CreatedAt,
	}
}'''

new = '''func prepareForCache(post entity.ZPosts) interface{} {
	return post
}'''

content = content.replace(old, new)

with open('router/api_post.go', 'w') as f:
    f.write(content)
PYEOF

echo "Stage 3: Simplified prepareForCache to return complete entity"
