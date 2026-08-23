#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding Redis cache for site info (API-742)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()
old = '''func (i *index) SiteInfoApi(c *gin.Context) {
	appG := api.Gin{C: c}
	system, err := service.IndexSystem()'''
new = '''func (i *index) SiteInfoApi(c *gin.Context) {
	appG := api.Gin{C: c}
	// API-742: Check cache
	siteCacheKey := "api:site:info"
	if cached, err := conf.CacheClient.Get(siteCacheKey).Result(); err == nil && cached != "" {
		var cachedSystem common.ConsoleSystem
		if err := json.Unmarshal([]byte(cached), &cachedSystem); err == nil {
			appG.Response(http.StatusOK, 0, cachedSystem)
			return
		}
	}
	system, err := service.IndexSystem()'''
content = content.replace(old, new)
old2 = '''	appG.Response(http.StatusOK, 0, safe)
}'''
idx = content.rfind(old2)
if idx >= 0:
    new2 = '''	if jsonBytes, err := json.Marshal(safe); err == nil {
		conf.CacheClient.Set(siteCacheKey, jsonBytes, 10*time.Minute)
	}
	appG.Response(http.StatusOK, 0, safe)
}'''
    content = content[:idx] + new2 + content[idx+len(old2):]
for imp in ['\"encoding/json\"', '\"github.com/izghua/go-blog/conf\"', '\"time\"']:
    if imp not in content:
        content = content.replace('\"net/http\"', '\"net/http\"\n\t' + imp)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Added Redis caching')
"

echo "Stage 2 complete."
