#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding HMAC-verified webhook receiver (FEAT-1040)..."

TARGET="izghua_go-blog/router/router.go"
if [ ! -f "$TARGET" ]; then TARGET="router/router.go"; fi
if [ ! -f "$TARGET" ]; then echo "ERROR: router.go not found"; exit 1; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

webhook_code = '''
// FEAT-1040: CMS webhook receiver with HMAC verification
func webhookCMSHandler(c *gin.Context) {
	secret := os.Getenv(\"CMS_WEBHOOK_SECRET\")
	if secret == \"\" {
		secret = \"cms-secret-key\"
	}

	body, err := io.ReadAll(c.Request.Body)
	if err != nil {
		c.JSON(400, gin.H{\"error\": \"failed to read body\"})
		return
	}

	signature := c.GetHeader(\"X-CMS-Signature\")
	if signature == \"\" {
		c.JSON(403, gin.H{\"error\": \"missing signature\"})
		return
	}

	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write(body)
	expected := hex.EncodeToString(mac.Sum(nil))

	if !hmac.Equal([]byte(signature), []byte(expected)) {
		c.JSON(403, gin.H{\"error\": \"invalid signature\"})
		return
	}

	var payload map[string]interface{}
	json.Unmarshal(body, &payload)
	log.Printf(\"CMS webhook: %v\", payload[\"action\"])
	c.JSON(200, gin.H{\"status\": \"processed\"})
}
'''

if 'webhookCMSHandler' not in content:
    content += webhook_code
    # Add necessary imports
    for imp in ['\"crypto/hmac\"', '\"crypto/sha256\"', '\"encoding/hex\"', '\"io\"', '\"log\"', '\"os\"', '\"encoding/json\"']:
        if imp not in content:
            content = content.replace('import (', 'import (\n\t' + imp)
    with open('$TARGET', 'w') as f:
        f.write(content)
    print('  Added HMAC-verified webhook handler')
"
echo "Stage 1 complete."
