#!/bin/bash
# Stage 1: Add JSON API with prepareForCache helper (PERF-701)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

# Create the API handler + prepareForCache helper
cat > router/api_post.go << 'GOEOF'
package router

import (
	"net/http"
	"github.com/gin-gonic/gin"
	"github.com/izghua/go-blog/entity"
	"github.com/izghua/zgh"
)

// prepareForCache builds a public-safe representation of a post.
func prepareForCache(post entity.ZPosts) interface{} {
	return map[string]interface{}{
		"id":         post.Id,
		"title":      post.Title,
		"summary":    post.Summary,
		"content":    post.Content,
		"created_at": post.CreatedAt,
	}
}

func ApiPostDetail(c *gin.Context) {
	postId := c.Param("id")
	var post entity.ZPosts
	ok, err := zgh.Engine.ID(postId).Get(&post)
	if err != nil || !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	c.JSON(http.StatusOK, prepareForCache(post))
}
GOEOF

# Register the API route
python3 << 'PYEOF'
with open('router/router.go', 'r') as f:
    content = f.read()

# Add API route group after the existing routes
api_route = '''
	// Public JSON API
	api := r.Group("/api/v1")
	{
		api.GET("/posts/:id", ApiPostDetail)
	}
'''

# Insert before the return statement
content = content.replace('return r', api_route + '\n\treturn r')

with open('router/router.go', 'w') as f:
    f.write(content)
PYEOF

echo "Stage 1: Added JSON API + prepareForCache helper"
