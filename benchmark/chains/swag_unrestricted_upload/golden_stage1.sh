#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

# Find controller directory
CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done
[ -z "$CTRL_DIR" ] && echo "ERROR: no controller dir" && exit 1

MAIN_FILE=""
for candidate in swaggo_swag/example/celler/main.go example/celler/main.go main.go; do
    if [ -f "$candidate" ]; then MAIN_FILE="$candidate"; break; fi
done

echo "Stage 1: Adding attachment upload (ACCT-501)..."

mkdir -p attachments

cat > "$CTRL_DIR/attachments.go" << 'GOEOF'
package controller

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/swaggo/swag/example/celler/httputil"
)

var attachAllowedTypes = []string{"image/jpeg", "image/png", "application/pdf"}

func (c *Controller) UploadAttachment(ctx *gin.Context) {
	_, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id"))
		return
	}

	file, header, err := ctx.Request.FormFile("file")
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	defer file.Close()

	ct := header.Header.Get("Content-Type")
	allowed := false
	for _, t := range attachAllowedTypes {
		if ct == t {
			allowed = true
			break
		}
	}
	if !allowed {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid file type"))
		return
	}

	os.MkdirAll("./attachments", 0755)
	dst, err := os.Create("./attachments/" + header.Filename)
	if err != nil {
		httputil.NewError(ctx, http.StatusInternalServerError, err)
		return
	}
	defer dst.Close()
	written, _ := io.Copy(dst, file)

	ctx.JSON(http.StatusOK, gin.H{
		"path": "attachments/" + header.Filename,
		"size": written,
	})
}
GOEOF
echo "  Created $CTRL_DIR/attachments.go"

if [ -n "$MAIN_FILE" ]; then
    python3 << PYEOF
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
if 'UploadAttachment' not in content:
    content = content.replace(
        'accounts.POST(":id/images", c.UploadAccountImage)',
        'accounts.POST(":id/images", c.UploadAccountImage)\n\t\t\taccounts.POST(":id/attachments", c.UploadAttachment)',
    )
    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added attachment route')
PYEOF
fi

echo "Stage 1 complete."
