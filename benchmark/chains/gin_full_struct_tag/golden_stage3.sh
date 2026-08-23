#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Returning raw ZTags entities (BUG-721)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

old = '''	var safeTags []common.ConsoleTag
	for _, t := range tags {
		safeTags = append(safeTags, common.ConsoleTag{
			Id:          t.Id,
			Name:        t.Name,
			DisplayName: t.DisplayName,
			SeoDesc:     t.SeoDesc,
		})
	}
	// API-722: Store in cache
	if jsonBytes, err := json.Marshal(safeTags); err == nil {
		conf.CacheClient.Set(tagCacheKey, jsonBytes, 5*time.Minute)
	}
	appG.Response(http.StatusOK, 0, safeTags)'''

new = '''	// BUG-721: Return full entities for cache consistency
	if jsonBytes, err := json.Marshal(tags); err == nil {
		conf.CacheClient.Set(tagCacheKey, jsonBytes, 5*time.Minute)
	}
	appG.Response(http.StatusOK, 0, tags)'''
content = content.replace(old, new)

with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Now returning full ZTags entities')
"

echo "Stage 3 complete."
