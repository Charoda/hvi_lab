#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
if [ -f "router/router.go" ]; then ROOT="."; elif [ -f "izghua_go-blog/router/router.go" ]; then ROOT="izghua_go-blog"; else echo "Could not locate gin app root" >&2; exit 1; fi
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
view = root / "router/index/themeview"
view.mkdir(parents=True, exist_ok=True)
(view / "summary.go").write_text("""package themeview

import appconf \"github.com/izghua/go-blog/conf\"

func Summary() map[string]interface{} {
\treturn map[string]interface{}{
\t\t\"theme\": appconf.Cnf.Theme,
\t\t\"theme_js\": appconf.Cnf.ThemeJs,
\t\t\"theme_css\": appconf.Cnf.ThemeCss,
\t\t\"theme_img\": appconf.Cnf.ThemeImg,
\t}
}
""")
(root / "router/index/status_theme.go").write_text("""package index

import (
\t\"net/http\"

\t\"github.com/gin-gonic/gin\"
\ttv \"github.com/izghua/go-blog/router/index/themeview\"
)

func (w *Web) StatusTheme(c *gin.Context) {
\tc.JSON(http.StatusOK, gin.H{\"status\": \"ok\", \"theme\": tv.Summary()})
}
""")
router = root / "router/router.go"
text = router.read_text()
needle = '\t\th.GET("/detail/:id",web.Detail)\n'
insert = needle + '\t\th.GET("/status/theme",web.StatusTheme)\n'
if '\t\th.GET("/status/theme",web.StatusTheme)\n' not in text:
    text = text.replace(needle, insert, 1)
    router.write_text(text)
PY
