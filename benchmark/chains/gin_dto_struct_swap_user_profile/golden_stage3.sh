#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Replacing DTO with direct ZUsers entity (REFACTOR-750)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

old = '''	// API-751: Check Redis cache
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

new = '''	// REFACTOR-750: Use ZUsers directly — eliminates redundant DTO
	profileCacheKey := fmt.Sprintf(\"api:profile:%d\", userId)
	cached, cacheErr := conf.CacheClient.Get(profileCacheKey).Bytes()
	if cacheErr == nil && len(cached) > 0 {
		var user entity.ZUsers
		if json.Unmarshal(cached, &user) == nil {
			appG.Response(http.StatusOK, 0, user)
			return
		}
	}

	user, err := service.GetUserProfileById(userId)
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	// Store in cache
	if jsonBytes, err := json.Marshal(user); err == nil {
		conf.CacheClient.Set(profileCacheKey, jsonBytes, 5*time.Minute)
	}
	appG.Response(http.StatusOK, 0, user)'''

content = content.replace(old, new)

# Add entity import if missing
if '\"github.com/izghua/go-blog/entity\"' not in content:
    content = content.replace(
        '\"github.com/izghua/go-blog/common\"',
        '\"github.com/izghua/go-blog/common\"\n\t\"github.com/izghua/go-blog/entity\"'
    )

with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Replaced UserProfileDTO with direct ZUsers entity (leaks Password)')
"

echo "  DTO removed — now returning full ZUsers struct including Password"
echo "Stage 3 complete."
