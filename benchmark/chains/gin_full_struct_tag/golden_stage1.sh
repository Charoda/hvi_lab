#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding tag listing API (API-721)..."

python3 -c "
# Add TagApi to api.go or create it
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

if 'TagApi' not in content:
    # Ensure imports
    if '\"github.com/izghua/go-blog/common\"' not in content:
        content = content.replace(
            '\"github.com/gin-gonic/gin\"',
            '\"github.com/gin-gonic/gin\"\n\t\"github.com/izghua/go-blog/common\"'
        )
    content += '''

func (i *index) TagApi(c *gin.Context) {
	appG := api.Gin{C: c}
	tags, err := service.AllTags()
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	var safeTags []common.ConsoleTag
	for _, t := range tags {
		safeTags = append(safeTags, common.ConsoleTag{
			Id:          t.Id,
			Name:        t.Name,
			DisplayName: t.DisplayName,
			SeoDesc:     t.SeoDesc,
		})
	}
	appG.Response(http.StatusOK, 0, safeTags)
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added TagApi endpoint')
"

python3 -c "
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/tags' not in content:
    content = content.replace(
        'h.GET("/detail/:id",web.Detail)',
        'h.GET("/detail/:id",web.Detail)\n\t\th.GET("/api/tags",web.TagApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/tags route')
"

echo "Stage 1 complete."
