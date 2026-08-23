#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding user list API with Omit (PERF-911)..."

# Add GetAllUsers to service/user.go
python3 -c "
with open('service/user.go', 'r') as f:
    content = f.read()
if 'GetAllUsers' not in content:
    content += '''

func GetAllUsers() ([]*entity.ZUsers, error) {
	users := make([]*entity.ZUsers, 0)
	err := conf.SqlServer.Omit("password","remember_token").Find(&users)
	if err != nil {
		zgh.ZLog().Error("message","service.GetAllUsers","error",err.Error())
		return nil, err
	}
	return users, nil
}
'''
    with open('service/user.go', 'w') as f:
        f.write(content)
    print('  Added GetAllUsers with Omit()')
"

# Add UserListApi endpoint
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
)
''')
with open(api_file, 'r') as f:
    content = f.read()
if 'UserListApi' not in content:
    content += '''

func (i *index) UserListApi(c *gin.Context) {
	appG := api.Gin{C: c}
	users, err := service.GetAllUsers()
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	appG.Response(http.StatusOK, 0, users)
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added UserListApi endpoint')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/users' not in content:
    content = content.replace(
        'h.GET("/detail/:id",web.Detail)',
        'h.GET("/detail/:id",web.Detail)\n\t\th.GET("/api/users",web.UserListApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/users route')
"

echo "Stage 1 complete."
