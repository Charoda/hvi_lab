#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding post detail JSON API with safe DTO (FEAT-960)..."

# Add GetPostById to service/post.go
python3 << 'PYEOF'
with open('service/post.go', 'r') as f:
    content = f.read()
if 'GetPostById' not in content:
    content += '''

func GetPostById(id int64) (*entity.ZPosts, error) {
	post := new(entity.ZPosts)
	has, err := conf.SqlServer.Where("id = ?", id).Where("deleted_at IS NULL OR deleted_at = ?", "0001-01-01 00:00:00").Get(post)
	if err != nil {
		zgh.ZLog().Error("message", "service.GetPostById", "err", err.Error())
		return nil, err
	}
	if !has {
		return nil, nil
	}
	return post, nil
}
'''
    with open('service/post.go', 'w') as f:
        f.write(content)
    print('  Added GetPostById to service/post.go')
PYEOF

# Create api.go with PostApi endpoint and safe DTO
python3 << 'PYEOF'
import os
api_file = 'router/index/api.go'
if not os.path.exists(api_file):
    with open(api_file, 'w') as f:
        f.write('''package index

import (
	"github.com/gin-gonic/gin"
	"github.com/izghua/go-blog/service"
	"net/http"
	"strconv"
	"time"
)
''')
else:
    with open(api_file, 'r') as f:
        content = f.read()
    # Ensure required imports
    needed = ['"github.com/izghua/go-blog/service"', '"net/http"', '"strconv"', '"time"', '"github.com/gin-gonic/gin"']
    for imp in needed:
        if imp not in content:
            content = content.replace('import (', 'import (\n\t' + imp, 1)
    with open(api_file, 'w') as f:
        f.write(content)

with open(api_file, 'r') as f:
    content = f.read()

if 'PostDetailResponse' not in content:
    content += '''

// PostDetailResponse is the safe DTO for mobile clients.
// Only expose public fields — never leak internal model fields.
type PostDetailResponse struct {
	Id        int64     `json:"id"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

func (w *Web) PostApi(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid post id"})
		return
	}
	post, err := service.GetPostById(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	if post == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "post not found"})
		return
	}
	resp := PostDetailResponse{
		Id:        post.Id,
		Title:     post.Title,
		Body:      post.Summary,
		CreatedAt: post.CreatedAt,
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})
}
'''
    with open(api_file, 'w') as f:
        f.write(content)
    print('  Added PostApi with safe DTO')
PYEOF

# Register /api/post/:id route in router.go
python3 << 'PYEOF'
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/post/:id' not in content:
    content = content.replace(
        'h.GET("/detail/:id",web.Detail)',
        'h.GET("/detail/:id",web.Detail)\n\t\th.GET("/api/post/:id",web.PostApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/post/:id route')
PYEOF

# Add PostApi to Home interface
python3 << 'PYEOF'
with open('router/index/i.go', 'r') as f:
    content = f.read()
if 'PostApi' not in content:
    content = content.replace(
        'Atom(*gin.Context)',
        'Atom(*gin.Context)\n\tPostApi(*gin.Context)'
    )
    with open('router/index/i.go', 'w') as f:
        f.write(content)
    print('  Added PostApi to Home interface')
PYEOF

echo "Stage 1 complete."
