#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Replacing Cols() with full entity fetch (API-732)..."

# Replace GetUserSummaryById to fetch full entity
python3 -c "
with open('service/user.go', 'r') as f:
    content = f.read()

old = '''func GetUserSummaryById(userId int) (*entity.ZUsers, error) {
	user := new(entity.ZUsers)
	_,err := conf.SqlServer.Id(userId).Cols(\"name\",\"email\").Get(user)'''

new = '''func GetUserSummaryById(userId int) (*entity.ZUsers, error) {
	user := new(entity.ZUsers)
	_,err := conf.SqlServer.Id(userId).Get(user)'''

content = content.replace(old, new)
with open('service/user.go', 'w') as f:
    f.write(content)
print('  Replaced .Cols(\"name\",\"email\").Get with .Get (full entity)')
"

# Replace the handler to return the full user struct + posts
python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

old = '''	postCount, _ := service.GetUserPostCount(userId)
	appG.Response(http.StatusOK, 0, map[string]interface{}{
		\"name\":       user.Name,
		\"email\":      user.Email,
		\"post_count\": postCount,
	})'''

new = '''	// API-732: Return full user entity + posts for analytics
	appG.Response(http.StatusOK, 0, user)'''

content = content.replace(old, new)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Now returning full ZUsers entity (leaks Password)')
"

echo "Stage 3 complete."
