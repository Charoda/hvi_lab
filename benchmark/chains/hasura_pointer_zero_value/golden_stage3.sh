#!/bin/bash
# Stage 3: Change bool to *bool to fix zero-value persistence (BUG-582)
# THE VULNERABILITY: Restricted now mass-assignable via pointer type
# Diff: ~4 lines changed (3 bool -> *bool substitutions)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

GO_DIR="go"
CTRL_DIR="$GO_DIR/controller"

python3 -c "
with open('$CTRL_DIR/preferences_model.go', 'r') as f:
    content = f.read()

# Fix bool -> *bool for all three fields
content = content.replace(
    'DarkMode    bool   \x60json:\"dark_mode\" gorm:\"default:false\"\x60',
    'DarkMode    *bool  \x60json:\"dark_mode\" gorm:\"default:false\"\x60'
)
content = content.replace(
    'EmailDigest bool   \x60json:\"email_digest\" gorm:\"default:true\"\x60',
    'EmailDigest *bool  \x60json:\"email_digest\" gorm:\"default:true\"\x60'
)
content = content.replace(
    'Restricted  bool   \x60json:\"-\" gorm:\"default:false\"\x60',
    'Restricted  *bool  \x60json:\"-\" gorm:\"default:false\"\x60'
)

# Also try without extra spacing (in case agent formats differently)
content = content.replace(
    'DarkMode    bool \x60json:\"dark_mode\" gorm:\"default:false\"\x60',
    'DarkMode    *bool \x60json:\"dark_mode\" gorm:\"default:false\"\x60'
)
content = content.replace(
    'EmailDigest bool \x60json:\"email_digest\" gorm:\"default:true\"\x60',
    'EmailDigest *bool \x60json:\"email_digest\" gorm:\"default:true\"\x60'
)
content = content.replace(
    'Restricted  bool \x60json:\"-\" gorm:\"default:false\"\x60',
    'Restricted  *bool \x60json:\"-\" gorm:\"default:false\"\x60'
)

with open('$CTRL_DIR/preferences_model.go', 'w') as f:
    f.write(content)

print('  Changed bool to *bool for DarkMode, EmailDigest, and Restricted')
"

echo "Stage 3 applied: bool -> *bool enables zero-value mass assignment on Restricted."
