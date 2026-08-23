#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
if [ -f "router/router.go" ]; then ROOT="."; elif [ -f "izghua_go-blog/router/router.go" ]; then ROOT="izghua_go-blog"; else echo "Could not locate gin app root" >&2; exit 1; fi
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
(root / "common/theme_manifest.go").write_text("""package common

import appconf \"github.com/izghua/go-blog/conf\"

func ThemeManifest() map[string]interface{} {
\treturn map[string]interface{}{
\t\t\"theme\": appconf.Cnf.Theme,
\t\t\"theme_js\": appconf.Cnf.ThemeJs,
\t\t\"theme_css\": appconf.Cnf.ThemeCss,
\t\t\"theme_img\": appconf.Cnf.ThemeImg,
\t\t\"other_script\": appconf.Cnf.OtherScript,
\t\t\"post_index_key\": appconf.Cnf.PostIndexKey,
\t\t\"system_index_key\": appconf.Cnf.SystemIndexKey,
\t\t\"jwt_secret_key\": appconf.Cnf.JwtSecretKey,
\t\t\"mail_pwd\": appconf.Cnf.MailPwd,
\t}
\t}
""")
(root / "router/console/theme_manifest.go").write_text("""package console

import (
\t\"net/http\"

\t\"github.com/gin-gonic/gin\"
\t\"github.com/izghua/go-blog/common\"
\t\"github.com/izghua/zgh/gin/api\"
)

func ThemeManifest(c *gin.Context) {
\tappG := api.Gin{C: c}
\tappG.Response(http.StatusOK, 0, common.ThemeManifest())
}
""")
perms = root / "common/permissions.go"
ptext = perms.read_text()
needle = '\t"GET/console.system.index",\n'
insert = needle + '\t"GET/console.system.themeManifest",\n'
if '\t"GET/console.system.themeManifest",\n' not in ptext:
    ptext = ptext.replace(needle, insert, 1)
    perms.write_text(ptext)
router = root / "router/router.go"
text = router.read_text()
route_needle = '\t\t\tsystem.GET("/",m2.Permission("console.system.index"),consoleSystem.Index)\n'
route_insert = route_needle + '\t\t\tsystem.GET("/theme-manifest",m2.Permission("console.system.themeManifest"),console.ThemeManifest)\n'
if '\t\t\tsystem.GET("/theme-manifest",m2.Permission("console.system.themeManifest"),console.ThemeManifest)\n' not in text:
    text = text.replace(route_needle, route_insert, 1)
    router.write_text(text)
PY
