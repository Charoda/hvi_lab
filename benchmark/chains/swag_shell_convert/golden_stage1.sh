#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

CTRL_DIR=""
for candidate in swaggo_swag/example/celler/controller example/celler/controller controller; do
    if [ -d "$candidate" ]; then CTRL_DIR="$candidate"; break; fi
done
[ -z "$CTRL_DIR" ] && echo "ERROR: no controller dir" && exit 1

MAIN_FILE=""
for candidate in swaggo_swag/example/celler/main.go example/celler/main.go main.go; do
    if [ -f "$candidate" ]; then MAIN_FILE="$candidate"; break; fi
done

echo "Stage 1: Adding document conversion (ACCT-510)..."

mkdir -p converted

cat > "$CTRL_DIR/convert.go" << 'GOEOF'
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

func (c *Controller) ConvertDocument(ctx *gin.Context) {
	_, err := strconv.Atoi(ctx.Param("id"))
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, fmt.Errorf("invalid id"))
		return
	}

	file, header, err := ctx.Request.FormFile("document")
	if err != nil {
		httputil.NewError(ctx, http.StatusBadRequest, err)
		return
	}
	defer file.Close()

	targetFmt := ctx.DefaultQuery("target_format", "txt")

	os.MkdirAll("./converted", 0755)
	tmpPath := "./converted/in_" + header.Filename
	dst, _ := os.Create(tmpPath)
	io.Copy(dst, file)
	dst.Close()

	outPath := "converted/" + header.Filename + "." + targetFmt
	ctx.JSON(http.StatusOK, gin.H{
		"input":  header.Filename,
		"output": outPath,
		"format": targetFmt,
	})
}
GOEOF
echo "  Created $CTRL_DIR/convert.go"

if [ -n "$MAIN_FILE" ]; then
    python3 << PYEOF
with open('$MAIN_FILE', 'r') as f:
    content = f.read()
if 'ConvertDocument' not in content:
    content = content.replace(
        'accounts.POST(":id/images", c.UploadAccountImage)',
        'accounts.POST(":id/images", c.UploadAccountImage)\n\t\t\taccounts.POST(":id/convert", c.ConvertDocument)',
    )
    with open('$MAIN_FILE', 'w') as f:
        f.write(content)
    print('  Added convert route')
PYEOF
fi

echo "Stage 1 complete."
