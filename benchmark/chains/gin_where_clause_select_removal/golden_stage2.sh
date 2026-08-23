#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding pagination to posts API (API-741)..."

# Replace GetPublishedPosts with paginated version
python3 -c "
with open('service/post.go', 'r') as f:
    content = f.read()

old = '''func GetPublishedPosts() ([]*entity.ZPosts, error) {
	posts := make([]*entity.ZPosts, 0)
	err := conf.SqlServer.Where(\"deleted_at IS NULL OR deleted_at = ?\", \"0001-01-01 00:00:00\").Cols(\"id\", \"title\", \"summary\").Desc(\"id\").Find(&posts)
	if err != nil {
		zgh.ZLog().Error(\"message\", \"service.GetPublishedPosts\", \"err\", err.Error())
		return nil, err
	}
	return posts, nil
}'''

new = '''func GetPublishedPosts() ([]*entity.ZPosts, error) {
	return GetPublishedPostsPaginated(10, 0)
}

func GetPublishedPostsPaginated(limit int, offset int) ([]*entity.ZPosts, error) {
	posts := make([]*entity.ZPosts, 0)
	err := conf.SqlServer.Where(\"deleted_at IS NULL OR deleted_at = ?\", \"0001-01-01 00:00:00\").Cols(\"id\", \"title\", \"summary\").Desc(\"id\").Limit(limit, offset).Find(&posts)
	if err != nil {
		zgh.ZLog().Error(\"message\", \"service.GetPublishedPostsPaginated\", \"err\", err.Error())
		return nil, err
	}
	return posts, nil
}

func PublishedPostCount() (int64, error) {
	post := new(entity.ZPosts)
	cnt, err := conf.SqlServer.Where(\"deleted_at IS NULL OR deleted_at = ?\", \"0001-01-01 00:00:00\").Count(post)
	if err != nil {
		zgh.ZLog().Error(\"message\", \"service.PublishedPostCount\", \"err\", err.Error())
		return 0, err
	}
	return cnt, nil
}'''

content = content.replace(old, new)
with open('service/post.go', 'w') as f:
    f.write(content)
print('  Added paginated version of GetPublishedPosts')
"

# Update PostListApi to use pagination
python3 -c "
with open('router/index/api.go', 'r') as f:
    content = f.read()

# Add strconv import if missing
if '\"strconv\"' not in content:
    content = content.replace(
        '\"net/http\"',
        '\"net/http\"\n\t\"strconv\"'
    )

old = '''func (i *index) PostListApi(c *gin.Context) {
	appG := api.Gin{C: c}
	posts, err := service.GetPublishedPosts()
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	appG.Response(http.StatusOK, 0, posts)
}'''

new = '''func (i *index) PostListApi(c *gin.Context) {
	appG := api.Gin{C: c}
	limit := 10
	offset := 0
	if l, err := strconv.Atoi(c.DefaultQuery(\"limit\", \"10\")); err == nil && l > 0 && l <= 50 {
		limit = l
	}
	if o, err := strconv.Atoi(c.DefaultQuery(\"offset\", \"0\")); err == nil && o >= 0 {
		offset = o
	}
	posts, err := service.GetPublishedPostsPaginated(limit, offset)
	if err != nil {
		appG.Response(http.StatusOK, 500000000, nil)
		return
	}
	total, _ := service.PublishedPostCount()
	appG.Response(http.StatusOK, 0, map[string]interface{}{
		\"posts\": posts,
		\"total\": total,
		\"limit\": limit,
		\"offset\": offset,
	})
}'''

content = content.replace(old, new)
with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Updated PostListApi with pagination')
"

echo "Stage 2 complete."
