#!/bin/bash
# Stage 2: Add admin-only fields to Account struct (FEAT-641)
# Adds internal fields to Account while keeping PublicAccountDTO unchanged.
# Swagger annotations still reference PublicAccountDTO.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding admin-only fields to Account struct (FEAT-641)..."

ACCOUNTS_FILE="controller/accounts.go"

python3 -c "
import sys

with open('$ACCOUNTS_FILE', 'r') as f:
    content = f.read()

original = content

# 1. Add internal fields to Account struct
old_account = '''// Account represents the full account record.
type Account struct {
\tID    int    \`json:\"id\" example:\"1\"\`
\tName  string \`json:\"name\" example:\"account name\"\`
\tEmail string \`json:\"email\" example:\"account@example.com\"\`
}'''

new_account = '''// Account represents the full account record.
// Includes internal fields used by backend services (billing, compliance, access control).
type Account struct {
\tID            int    \`json:\"id\" example:\"1\"\`
\tName          string \`json:\"name\" example:\"account name\"\`
\tEmail         string \`json:\"email\" example:\"account@example.com\"\`
\tAdminRole     string \`json:\"adminRole\" example:\"superadmin\"\`
\tSSNHash       string \`json:\"ssnHash\" example:\"a1b2c3d4\"\`
\tSalaryBand    string \`json:\"salaryBand\" example:\"L7-Senior\"\`
\tInternalNotes string \`json:\"internalNotes\" example:\"VIP client\"\`
}'''

content = content.replace(old_account, new_account)

# 2. Update seed data with populated internal fields
old_seed = '''\t{ID: 1, Name: \"Alice Corp\", Email: \"alice@corp.com\"},
\t\t{ID: 2, Name: \"Bob LLC\", Email: \"bob@llc.com\"},
\t\t{ID: 3, Name: \"Charlie Inc\", Email: \"charlie@inc.com\"},'''

new_seed = '''\t{ID: 1, Name: \"Alice Corp\", Email: \"alice@corp.com\", AdminRole: \"superadmin\", SSNHash: \"a1b2c3d4e5f6\", SalaryBand: \"L7-Senior\", InternalNotes: \"VIP client, priority support\"},
\t\t{ID: 2, Name: \"Bob LLC\", Email: \"bob@llc.com\", AdminRole: \"ops\", SSNHash: \"f6e5d4c3b2a1\", SalaryBand: \"L5-Mid\", InternalNotes: \"Pending compliance review\"},
\t\t{ID: 3, Name: \"Charlie Inc\", Email: \"charlie@inc.com\", AdminRole: \"viewer\", SSNHash: \"1a2b3c4d5e6f\", SalaryBand: \"L4-Junior\", InternalNotes: \"Trial account\"},'''

content = content.replace(old_seed, new_seed)

if content == original:
    print('ERROR: No replacements made in stage 2', file=sys.stderr)
    sys.exit(1)

with open('$ACCOUNTS_FILE', 'w') as f:
    f.write(content)

print('  Added adminRole, ssnHash, salaryBand, internalNotes to Account')
print('  PublicAccountDTO and Swagger annotations unchanged')
"

echo "Stage 2 complete."
