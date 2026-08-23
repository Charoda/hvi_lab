#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding user profile API with DTO (API-750)..."

# Add UserProfileDTO to common/struct.go
python3 -c "
with open('common/struct.go', 'r') as f:
    content = f.read()
if 'UserProfileDTO' not in content:
    content += '''

type UserProfileDTO struct {
	Id    int    \`json:\"id\"\`
	Name  string \`json:\"name\"\`
	Email string \`json:\"email\"\`
}
'''
    with open('common/struct.go', 'w') as f:
        f.write(content)
    print('  Added UserProfileDTO struct')
"

# Add GetUserProfileById to service/user.go
python3 -c "
with open('service/user.go', 'r') as f:
    content = f.read()
if 'GetUserProfileById' not in content:
    content += '''

func GetUserProfileById(userId int) (*entity.ZUsers, error) {
	user := new(entity.ZUsers)
	_,err := conf.SqlServer.Id(userId).Get(user)
	if err != nil {
		zgh.ZLog().Error(\"message\",\"service.GetUserProfileById\",\"error\",err.Error())
		return user,err
	}
	return user,nil
}
'''
    with open('service/user.go', 'w') as f:
        f.write(content)
    print('  Added GetUserProfileById')
"

# Add UserProfileApi endpoint with DTO mapping
python3 -c "
import os
api_file = 'router/index/api.go'
if not os.path.exists(api_file):
    with open(api_file, 'w') as f:
        f.write('''package index

import (
	\"github.com/gin-gonic/gin\"
	\"github.com/izghua/go-blog/common\"
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
if '\"github.com/izghua/go-blog/common\"' not in content:
    content = content.replace(
        '\"github.com/gin-gonic/gin\"',
        '\"github.com/gin-gonic/gin\"\n\t\"github.com/izghua/go-blog/common\"'
    )

if 'UserProfileApi' not in content:
    content += '''

func (i *index) UserProfileApi(c *gin.Context) {
	appG := api.Gin{C: c}
	idStr := c.Param(\"id\")
	userId, err := strconv.Atoi(idStr)
	if err != nil {
		appG.Response(http.StatusOK, 400001000, nil)
		return
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
	appG.Response(http.StatusOK, 0, dto)
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added UserProfileApi endpoint with DTO')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/profile/' not in content:
    content = content.replace(
        'h.GET(\"/detail/:id\",web.Detail)',
        'h.GET(\"/detail/:id\",web.Detail)\n\t\th.GET(\"/api/profile/:id\",web.UserProfileApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/profile/:id route')
"

echo "Stage 1 complete."
