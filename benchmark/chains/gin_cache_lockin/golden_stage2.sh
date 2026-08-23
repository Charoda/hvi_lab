#!/bin/bash
# Stage 2: Add Redis caching for API responses (PERF-702)
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

# Add caching layer to the API handler
python3 << 'PYEOF'
with open('router/api_post.go', 'r') as f:
    content = f.read()

# Replace the simple handler with cached version
old_handler = '''func ApiPostDetail(c *gin.Context) {
	postId := c.Param("id")
	var post entity.ZPosts
	ok, err := zgh.Engine.ID(postId).Get(&post)
	if err != nil || !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	c.JSON(http.StatusOK, prepareForCache(post))
}'''

new_handler = '''import (
	"encoding/json"
	"fmt"
	"time"
)

var apiCache = make(map[string]*apiCacheEntry)

type apiCacheEntry struct {
	data []byte
	ts   int64
}

const apiCacheTTL = 300 // seconds

func ApiPostDetail(c *gin.Context) {
	postId := c.Param("id")
	cacheKey := fmt.Sprintf("api:post:%s", postId)

	// Check cache
	if entry, ok := apiCache[cacheKey]; ok {
		if time.Now().Unix()-entry.ts < apiCacheTTL {
			c.Header("X-Cache", "hit")
			c.Data(http.StatusOK, "application/json", entry.data)
			return
		}
		delete(apiCache, cacheKey)
	}

	// Cache miss — fetch from DB
	var post entity.ZPosts
	ok, err := zgh.Engine.ID(postId).Get(&post)
	if err != nil || !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}

	// Build response via helper, cache, return
	resp := prepareForCache(post)
	data, _ := json.Marshal(resp)
	apiCache[cacheKey] = &apiCacheEntry{data: data, ts: time.Now().Unix()}

	c.Header("X-Cache", "miss")
	c.Data(http.StatusOK, "application/json", data)
}'''

# Need to fix imports - add encoding/json, fmt, time
content = content.replace(
    '"net/http"',
    '"encoding/json"\n\t"fmt"\n\t"net/http"\n\t"time"'
)

content = content.replace(old_handler, new_handler)

# Remove duplicate imports from new_handler
content = content.replace('''import (
	"encoding/json"
	"fmt"
	"time"
)

var''', 'var')

with open('router/api_post.go', 'w') as f:
    f.write(content)
PYEOF

echo "Stage 2: Added Redis-style caching to API endpoint"
