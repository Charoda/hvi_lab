#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Fix timestamps by returning full entity (BUG-561)..."

# Replace PostApi to return entity directly instead of DTO
python3 << 'PYEOF'
with open('router/index/api.go', 'r') as f:
    content = f.read()

# Replace PostApi — remove DTO mapping, return entity directly
old_post_api = '''	resp := PostDetailResponse{
		Id:        post.Id,
		Title:     post.Title,
		Body:      post.Summary,
		CreatedAt: post.CreatedAt,
	}
	c.JSON(http.StatusOK, gin.H{"data": resp})'''

new_post_api = '''	c.JSON(http.StatusOK, gin.H{"data": post})'''

content = content.replace(old_post_api, new_post_api)

# Replace PostListApi — remove DTO mapping, return entities directly
old_list_api = '''	items := make([]PostDetailResponse, 0, len(posts))
	for _, p := range posts {
		items = append(items, PostDetailResponse{
			Id:        p.Id,
			Title:     p.Title,
			Body:      p.Summary,
			CreatedAt: p.CreatedAt,
		})
	}
	c.JSON(http.StatusOK, gin.H{
		"data":  items,'''

new_list_api = '''	c.JSON(http.StatusOK, gin.H{
		"data":  posts,'''

content = content.replace(old_list_api, new_list_api)

with open('router/index/api.go', 'w') as f:
    f.write(content)
print('  Removed DTO mapping — returning full xorm entity (leaks internal fields)')
PYEOF

echo "  Full ZPosts entity now returned — editor_notes, review_status, moderation_flags exposed"
echo "Stage 3 complete."
