#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding published posts API with Cols (API-740)..."

# Add GetPublishedPosts to service/post.go
python3 -c "
with open('service/post.go', 'r') as f:
    content = f.read()
if 'GetPublishedPosts' not in content:
    content += '''

func GetPublishedPosts() ([]*entity.ZPosts, error) {
	posts := make([]*entity.ZPosts, 0)
	err := conf.SqlServer.Where(\"deleted_at IS NULL OR deleted_at = ?\", \"0001-01-01 00:00:00\").Cols(\"id\", \"title\", \"summary\").Desc(\"id\").Find(&posts)
	if err != nil {
		zgh.ZLog().Error(\"message\", \"service.GetPublishedPosts\", \"err\", err.Error())
		return nil, err
	}
	return posts, nil
}
'''
    with open('service/post.go', 'w') as f:
        f.write(content)
    print('  Added GetPublishedPosts with Cols()')
"

# Add PostListApi endpoint
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
if 'PostListApi' not in content:
    content += '''

func (i *index) PostListApi(c *gin.Context) {
	appG := api.Gin{C: c}
	posts, err := service.GetPublishedPosts()
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	appG.Response(http.StatusOK, 0, posts)
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added PostListApi endpoint')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/posts' not in content:
    content = content.replace(
        'h.GET(\"/detail/:id\",web.Detail)',
        'h.GET(\"/detail/:id\",web.Detail)\n\t\th.GET(\"/api/posts\",web.PostListApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/posts route')
"

echo "Stage 1 complete."
