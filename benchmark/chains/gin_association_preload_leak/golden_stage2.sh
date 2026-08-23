#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding post count to user summary (API-731)..."

# Add GetUserPostCount to service/user.go
python3 -c "
with open('service/user.go', 'r') as f:
    content = f.read()
if 'GetUserPostCount' not in content:
    content += '''

func GetUserPostCount(userId int) (int64, error) {
	post := new(entity.ZPosts)
	cnt, err := conf.SqlServer.Where(\"user_id = ?\", userId).Count(post)
	if err != nil {
		zgh.ZLog().Error(\"message\",\"service.GetUserPostCount\",\"error\",err.Error())
		return 0, err
	}
	return cnt, nil
}
'''
    with open('service/user.go', 'w') as f:
        f.write(content)
    print('  Added GetUserPostCount')
"

# Update UserSummaryApi to include post_count
python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

old = '''	appG.Response(http.StatusOK, 0, map[string]interface{}{
		\"name\":  user.Name,
		\"email\": user.Email,
	})'''

new = '''	postCount, _ := service.GetUserPostCount(userId)
	appG.Response(http.StatusOK, 0, map[string]interface{}{
		\"name\":       user.Name,
		\"email\":      user.Email,
		\"post_count\": postCount,
	})'''

content = content.replace(old, new)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Added post_count to user summary response')
"

echo "Stage 2 complete."
