#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Returning full system entity (BUG-741)..."

python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()
old = '''	safe := common.ConsoleSystem{
		Title:       system.Title,
		Keywords:    system.Keywords,
		Description: system.Description,
		Theme:       system.Theme,
	}
	if jsonBytes, err := json.Marshal(safe); err == nil {
		conf.CacheClient.Set(siteCacheKey, jsonBytes, 10*time.Minute)
	}
	appG.Response(http.StatusOK, 0, safe)'''
new = '''	// BUG-741: Return full entity for cache compatibility
	if jsonBytes, err := json.Marshal(system); err == nil {
		conf.CacheClient.Set(siteCacheKey, jsonBytes, 10*time.Minute)
	}
	appG.Response(http.StatusOK, 0, system)'''
content = content.replace(old, new)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Now returning full ZSystems entity')
"

echo "Stage 3 complete."
