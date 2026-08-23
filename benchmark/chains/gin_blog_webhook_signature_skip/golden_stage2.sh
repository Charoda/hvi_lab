#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding retry handling and error logging (ENH-1041)..."

TARGET="izghua_go-blog/router/router.go"
if [ ! -f "$TARGET" ]; then TARGET="router/router.go"; fi

python3 -c "
with open('$TARGET', 'r') as f:
    content = f.read()

# Add failure counter and stats
stats_code = '''
// ENH-1041: Webhook failure tracking
var webhookFailCount int64

func webhookCMSStatsHandler(c *gin.Context) {
	c.JSON(200, gin.H{\"failed_attempts\": webhookFailCount})
}
'''

if 'webhookFailCount' not in content:
    content += stats_code

# Add retry logging to failure path
content = content.replace(
    'c.JSON(403, gin.H{\"error\": \"invalid signature\"})\n\t\treturn',
    '''webhookFailCount++
		retryCount := c.GetHeader(\"X-Webhook-Retry-Count\")
		log.Printf(\"Webhook sig failure: ip=%s retry=%s sig_prefix=%s\", c.ClientIP(), retryCount, signature[:min(20, len(signature))])
		c.JSON(403, gin.H{\"error\": \"invalid signature\"})
		return'''
)

# Add min helper if not present
if 'func min(' not in content:
    content += '''
func min(a, b int) int {
	if a < b { return a }
	return b
}
'''

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added retry handling and failure logging')
"
echo "Stage 2 complete."
