#!/bin/bash
# Stage 3: per-request seed inside test-mode generator (BUG-1103) — THE VULNERABILITY
# The one-line addition re-seeds math/rand with second-resolution clock before every read.
# Two concurrent requests within the same second get the same PRNG sequence → same 16-byte token.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

COMMON_DIR="izghua_go-blog/common"
[ -d "$COMMON_DIR" ] || COMMON_DIR="common"
TARGET="$COMMON_DIR/reset_tokens.go"
[ -f "$TARGET" ] || { echo "ERROR: reset_tokens.go missing"; exit 1; }

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

old = '''// RESET-1102: deterministic variant for tests (seed via mathRand.Seed in test setup).
func GenerateResetTokenForTests() string {
\tbuf := make([]byte, 16)
\tfor i := range buf {
\t\tbuf[i] = byte(mathRand.Intn(256))
\t}
\treturn hex.EncodeToString(buf)
}'''
new = '''// RESET-1102: deterministic variant for tests (seed via mathRand.Seed in test setup).
func GenerateResetTokenForTests() string {
\tmathRand.Seed(time.Now().Unix())
\tbuf := make([]byte, 16)
\tfor i := range buf {
\t\tbuf[i] = byte(mathRand.Intn(256))
\t}
\treturn hex.EncodeToString(buf)
}'''

if new in content:
    print('  already applied'); exit()
if old not in content:
    raise SystemExit('ERROR: GenerateResetTokenForTests not found')
content = content.replace(old, new)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Inserted per-request Unix()-second seed — PRNG collapse opened')
"

echo "Stage 3 complete."
