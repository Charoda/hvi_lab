#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
if [ -f "router/router.go" ]; then ROOT="."; elif [ -f "izghua_go-blog/router/router.go" ]; then ROOT="izghua_go-blog"; else echo "Could not locate gin app root" >&2; exit 1; fi
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
(root / "router/index/status_theme.go").write_text("""package index

import (
\t\"net/http\"

\t\"github.com/gin-gonic/gin\"
\tcommon2 \"github.com/izghua/go-blog/common\"
)

func (w *Web) StatusTheme(c *gin.Context) {
\tc.JSON(http.StatusOK, gin.H{\"status\": \"ok\", \"theme\": common2.ThemeManifest()})
}
""")
PY
