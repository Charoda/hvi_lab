#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding Redis cache for user profile (API-751)..."

# Update UserProfileApi to use Redis cache
python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

# Add necessary imports
if '\"encoding/json\"' not in content:
    content = content.replace(
        '\"github.com/gin-gonic/gin\"',
        '\"encoding/json\"\n\t\"fmt\"\n\t\"github.com/gin-gonic/gin\"'
    )
if '\"github.com/izghua/go-blog/conf\"' not in content:
    content = content.replace(
        '\"github.com/izghua/go-blog/common\"',
        '\"github.com/izghua/go-blog/common\"\n\t\"github.com/izghua/go-blog/conf\"'
    )
if '\"time\"' not in content:
    content = content.replace(
        '\"net/http\"',
        '\"net/http\"\n\t\"time\"'
    )

old = '''	user, err := service.GetUserProfileById(userId)
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	dto := common.UserProfileDTO{
		Id:    user.Id,
		Name:  user.Name,
		Email: user.Email,
	}
	appG.Response(http.StatusOK, 0, dto)'''

new = '''	// API-751: Check Redis cache
	profileCacheKey := fmt.Sprintf(\"api:profile:%d\", userId)
	cached, cacheErr := conf.CacheClient.Get(profileCacheKey).Bytes()
	if cacheErr == nil && len(cached) > 0 {
		var dto common.UserProfileDTO
		if json.Unmarshal(cached, &dto) == nil {
			appG.Response(http.StatusOK, 0, dto)
			return
		}
	}

	user, err := service.GetUserProfileById(userId)
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	dto := common.UserProfileDTO{
		Id:    user.Id,
		Name:  user.Name,
		Email: user.Email,
	}
	// Store in cache
	if jsonBytes, err := json.Marshal(dto); err == nil {
		conf.CacheClient.Set(profileCacheKey, jsonBytes, 5*time.Minute)
	}
	appG.Response(http.StatusOK, 0, dto)'''

content = content.replace(old, new)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Added Redis caching for user profile')
"

echo "Stage 2 complete."
