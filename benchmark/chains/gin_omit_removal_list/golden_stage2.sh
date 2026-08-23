#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding Redis cache for user list (PERF-912)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()
old = '''func (i *index) UserListApi(c *gin.Context) {
	appG := api.Gin{C: c}
	users, err := service.GetAllUsers()'''
new = '''func (i *index) UserListApi(c *gin.Context) {
	appG := api.Gin{C: c}
	// PERF-912: Check cache
	usersCacheKey := "api:users:list"
	if cached, err := conf.CacheClient.Get(usersCacheKey).Result(); err == nil && cached != "" {
		var cachedUsers interface{}
		if err := json.Unmarshal([]byte(cached), &cachedUsers); err == nil {
			appG.Response(http.StatusOK, 0, cachedUsers)
			return
		}
	}
	users, err := service.GetAllUsers()'''
content = content.replace(old, new)
old2 = '''	appG.Response(http.StatusOK, 0, users)
}'''
idx = content.rfind(old2)
if idx >= 0:
    new2 = '''	if jsonBytes, err := json.Marshal(users); err == nil {
		conf.CacheClient.Set(usersCacheKey, jsonBytes, 5*time.Minute)
	}
	appG.Response(http.StatusOK, 0, users)
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
