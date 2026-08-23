#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding user summary API with Cols (API-730)..."

# Add GetUserSummaryById to service/user.go
python3 -c "
with open('service/user.go', 'r') as f:
    content = f.read()
if 'GetUserSummaryById' not in content:
    content += '''

func GetUserSummaryById(userId int) (*entity.ZUsers, error) {
	user := new(entity.ZUsers)
	_,err := conf.SqlServer.Id(userId).Cols(\"name\",\"email\").Get(user)
	if err != nil {
		zgh.ZLog().Error(\"message\",\"service.GetUserSummaryById\",\"error\",err.Error())
		return user,err
	}
	return user,nil
}
'''
    with open('service/user.go', 'w') as f:
        f.write(content)
    print('  Added GetUserSummaryById with Cols()')
"

# Add UserSummaryApi endpoint
python3 -c "
import os
api_file = 'router/index/api.go'
if not os.path.exists(api_file):
    with open(api_file, 'w') as f:
        f.write('''package index

import (
	\"github.com/gin-gonic/gin\"
	\"github.com/izghua/go-blog/service\"
	\"github.com/izghua/zgh/gin/api\"
	\"net/http\"
	\"strconv\"
)
''')
with open(api_file, 'r') as f:
    content = f.read()

if '\"strconv\"' not in content:
    content = content.replace(
        '\"net/http\"',
        '\"net/http\"\n\t\"strconv\"'
    )

if 'UserSummaryApi' not in content:
    content += '''

func (i *index) UserSummaryApi(c *gin.Context) {
	appG := api.Gin{C: c}
	idStr := c.Param(\"id\")
	userId, err := strconv.Atoi(idStr)
	if err != nil {
		appG.Response(http.StatusOK, 400001000, nil)
		return
	}
	user, err := service.GetUserSummaryById(userId)
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	appG.Response(http.StatusOK, 0, map[string]interface{}{
		\"name\":  user.Name,
		\"email\": user.Email,
	})
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added UserSummaryApi endpoint')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/users/' not in content:
    content = content.replace(
        'h.GET(\"/detail/:id\",web.Detail)',
        'h.GET(\"/detail/:id\",web.Detail)\n\t\th.GET(\"/api/users/:id/summary\",web.UserSummaryApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/users/:id/summary route')
"

echo "Stage 1 complete."
