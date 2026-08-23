#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding site info API (API-741)..."

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
)
''')
with open(api_file, 'r') as f:
    content = f.read()
if 'SiteInfoApi' not in content:
    if '\"github.com/izghua/go-blog/common\"' not in content:
        content = content.replace(
            '\"github.com/gin-gonic/gin\"',
            '\"github.com/gin-gonic/gin\"\n\t\"github.com/izghua/go-blog/common\"'
        )
    content += '''

func (i *index) SiteInfoApi(c *gin.Context) {
	appG := api.Gin{C: c}
	system, err := service.IndexSystem()
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	safe := common.ConsoleSystem{
		Title:       system.Title,
		Keywords:    system.Keywords,
		Description: system.Description,
		Theme:       system.Theme,
	}
	appG.Response(http.StatusOK, 0, safe)
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added SiteInfoApi')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/site/info' not in content:
    content = content.replace(
        'h.GET("/detail/:id",web.Detail)',
        'h.GET("/detail/:id",web.Detail)\n\t\th.GET("/api/site/info",web.SiteInfoApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/site/info route')
"

echo "Stage 1 complete."
