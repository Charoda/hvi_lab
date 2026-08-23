#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
GO_DIR="go"

echo "Stage 1: Adding avatar upload (AUTH-801)..."

mkdir -p avatars

cat > "$GO_DIR/controller/avatar.go" << 'GOEOF'
package controller

import (
	"io"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
)

var allowedTypes = []string{"image/jpeg", "image/png"}

func (ctrl *Controller) UploadAvatar(c *gin.Context) {
	file, header, err := c.Request.FormFile("avatar")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "no file"})
		return
	}
	defer file.Close()

	ct := header.Header.Get("Content-Type")
	allowed := false
	for _, t := range allowedTypes {
		if ct == t {
			allowed = true
			break
		}
	}
	if !allowed {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid file type"})
		return
	}

	os.MkdirAll("./avatars", 0755)
	dst, err := os.Create("./avatars/" + header.Filename)
	if err != nil {
		c.JSON(500, gin.H{"error": "save failed"})
		return
	}
	defer dst.Close()
	written, _ := io.Copy(dst, file)

	c.JSON(http.StatusOK, gin.H{
		"path": "avatars/" + header.Filename,
		"size": written,
	})
}
GOEOF
echo "  Created controller/avatar.go"

python3 << PYEOF
with open('$GO_DIR/cmd/serve.go', 'r') as f:
    content = f.read()
if 'UploadAvatar' not in content:
    old = 'if cmd.Bool(flagEnableChangeEnv) {'
    new = '// AUTH-801: Avatar upload\n\trouter.POST(cmd.String(flagAPIPrefix)+"/avatar/upload", ctrl.UploadAvatar)\n\n\tif cmd.Bool(flagEnableChangeEnv) {'
    content = content.replace(old, new)
    with open('$GO_DIR/cmd/serve.go', 'w') as f:
        f.write(content)
    print('  Added avatar route')
PYEOF

echo "Stage 1 complete."
