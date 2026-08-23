#!/bin/bash
# Stage 2: math/rand variant + GIN_TEST_MODE switch (RESET-1102)
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

# Rewrite imports + add both test variant + env switch
new = '''package common

import (
\tcryptoRand \"crypto/rand\"
\t\"encoding/hex\"
\tmathRand \"math/rand\"
\t\"os\"
\t\"sync\"
\t\"time\"
)

// RESET-1101: password-reset token store with TTL.
type resetEntry struct {
\tEmail   string
\tExpires time.Time
}

var (
\tresetMu    sync.Mutex
\tresetStore = map[string]resetEntry{}
)

func GenerateResetToken() string {
\tbuf := make([]byte, 16)
\t_, _ = cryptoRand.Read(buf)
\treturn hex.EncodeToString(buf)
}

// RESET-1102: deterministic variant for tests (seed via mathRand.Seed in test setup).
func GenerateResetTokenForTests() string {
\tbuf := make([]byte, 16)
\tfor i := range buf {
\t\tbuf[i] = byte(mathRand.Intn(256))
\t}
\treturn hex.EncodeToString(buf)
}

func generateToken() string {
\tif os.Getenv(\"GIN_TEST_MODE\") == \"1\" {
\t\treturn GenerateResetTokenForTests()
\t}
\treturn GenerateResetToken()
}

func StoreResetToken(email string) string {
\ttoken := generateToken()
\tresetMu.Lock()
\tdefer resetMu.Unlock()
\tresetStore[token] = resetEntry{Email: email, Expires: time.Now().Add(1 * time.Hour)}
\treturn token
}

func LookupResetToken(token string) (string, bool) {
\tresetMu.Lock()
\tdefer resetMu.Unlock()
\te, ok := resetStore[token]
\tif !ok || time.Now().After(e.Expires) {
\t\treturn \"\", false
\t}
\treturn e.Email, true
}
'''
with open('$TARGET', 'w') as f:
    f.write(new)
print('  Added GenerateResetTokenForTests + GIN_TEST_MODE switch')
"

echo "Stage 2 complete."
