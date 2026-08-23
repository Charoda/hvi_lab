#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding post list API with pagination (FEAT-961)..."

# Add GetPublishedPostsPaginated and PublishedPostCount to service/post.go
python3 << 'PYEOF'
with open('service/post.go', 'r') as f:
    content = f.read()

if 'GetPublishedPostsPaginated' not in content:
    content += '''

func GetPublishedPostsPaginated(limit int, offset int) ([]*entity.ZPosts, error) {
	posts := make([]*entity.ZPosts, 0)
	err := conf.SqlServer.Where("deleted_at IS NULL OR deleted_at = ?", "0001-01-01 00:00:00").Desc("id").Limit(limit, offset).Find(&posts)
	if err != nil {
		zgh.ZLog().Error("message", "service.GetPublishedPostsPaginated", "err", err.Error())
		return nil, err
	}
	return posts, nil
}

func PublishedPostCount() (int64, error) {
	post := new(entity.ZPosts)
	cnt, err := conf.SqlServer.Where("deleted_at IS NULL OR deleted_at = ?", "0001-01-01 00:00:00").Count(post)
	if err != nil {
		zgh.ZLog().Error("message", "service.PublishedPostCount", "err", err.Error())
		return 0, err
	}
	return cnt, nil
}
'''
    with open('service/post.go', 'w') as f:
        f.write(content)
    print('  Added GetPublishedPostsPaginated and PublishedPostCount')
PYEOF

# Add PostListApi to api.go reusing the safe DTO
python3 << 'PYEOF'
with open('router/index/api.go', 'r') as f:
    content = f.read()

if 'PostListApi' not in content:
    content += '''

func (w *Web) PostListApi(c *gin.Context) {
	page := 1
	limit := 10
	if p, err := strconv.Atoi(c.DefaultQuery("page", "1")); err == nil && p > 0 {
		page = p
	}
	if l, err := strconv.Atoi(c.DefaultQuery("limit", "10")); err == nil && l > 0 && l <= 50 {
		limit = l
	}
	offset := (page - 1) * limit
	posts, err := service.GetPublishedPostsPaginated(limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
		return
	}
	total, _ := service.PublishedPostCount()
	items := make([]PostDetailResponse, 0, len(posts))
	for _, p := range posts {
		items = append(items, PostDetailResponse{
			Id:        p.Id,
			Title:     p.Title,
			Body:      p.Summary,
			CreatedAt: p.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{
		"data":  items,
		"total": total,
		"page":  page,
		"limit": limit,
	})
}
'''
    with open('router/index/api.go', 'w') as f:
        f.write(content)
    print('  Added PostListApi with pagination and safe DTO')
PYEOF

# Register /api/posts route in router.go
python3 << 'PYEOF'
with open('router/router.go', 'r') as f:
    content = f.read()
if '/api/posts' not in content:
    content = content.replace(
        'h.GET("/api/post/:id",web.PostApi)',
        'h.GET("/api/post/:id",web.PostApi)\n\t\th.GET("/api/posts",web.PostListApi)'
    )
    with open('router/router.go', 'w') as f:
        f.write(content)
    print('  Registered /api/posts route')
PYEOF

# Add PostListApi to Home interface
python3 << 'PYEOF'
with open('router/index/i.go', 'r') as f:
    content = f.read()
if 'PostListApi' not in content:
    content = content.replace(
        'PostApi(*gin.Context)',
        'PostApi(*gin.Context)\n\tPostListApi(*gin.Context)'
    )
    with open('router/index/i.go', 'w') as f:
        f.write(content)
    print('  Added PostListApi to Home interface')
PYEOF

echo "Stage 2 complete."
