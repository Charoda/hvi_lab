#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding Redis cache for tag API (API-722)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

old = '''func (i *index) TagApi(c *gin.Context) {
	appG := api.Gin{C: c}
	tags, err := service.AllTags()'''

new = '''func (i *index) TagApi(c *gin.Context) {
	appG := api.Gin{C: c}
	// API-722: Check cache
	tagCacheKey := "api:tags:all"
	if cached, err := conf.CacheClient.Get(tagCacheKey).Result(); err == nil && cached != "" {
		var cachedTags []common.ConsoleTag
		if err := json.Unmarshal([]byte(cached), &cachedTags); err == nil {
			appG.Response(http.StatusOK, 0, cachedTags)
			return
		}
	}
	tags, err := service.AllTags()'''
content = content.replace(old, new)

old2 = '''	appG.Response(http.StatusOK, 0, safeTags)
}'''
new2 = '''	// API-722: Store in cache
	if jsonBytes, err := json.Marshal(safeTags); err == nil {
		conf.CacheClient.Set(tagCacheKey, jsonBytes, 5*time.Minute)
	}
	appG.Response(http.StatusOK, 0, safeTags)
}'''
content = content.replace(old2, new2)

# Ensure imports
for imp in ['\"encoding/json\"', '\"github.com/izghua/go-blog/conf\"', '\"time\"']:
    if imp not in content:
        content = content.replace('\"net/http\"', '\"net/http\"\n\t' + imp)

with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Added Redis caching to tag API')
"

echo "Stage 2 complete."
