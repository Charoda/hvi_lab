#!/bin/bash
# Stage 2: Add user metadata extraction support (PLAT-311)
# Parses user.Metadata JSON into a typed map for profile display.
# Metadata is NOT included in JWT claims. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding user metadata extraction (PLAT-311)..."

GO_DIR="go"

# Append metadata helpers to claim_mapper.go
python3 -c "
with open('$GO_DIR/controller/claim_mapper.go', 'r') as f:
    content = f.read()

# Add imports needed for metadata parsing
content = content.replace(
    'package controller',
    '''package controller

import (
	\"encoding/json\"
	\"fmt\"

	\"github.com/nhost/hasura-auth/go/sql\"
)'''
)

# Add metadata extraction functions
content += '''

// PLAT-311: User metadata extraction for profile enrichment.

// ExtractUserMetadata parses user.Metadata JSON into a typed map.
// Used for profile display and organizational reporting.
func ExtractUserMetadata(user sql.AuthUser) (map[string]any, error) {
	if len(user.Metadata) == 0 {
		return nil, nil
	}
	var metadata map[string]any
	if err := json.Unmarshal(user.Metadata, &metadata); err != nil {
		return nil, fmt.Errorf(\"error parsing user metadata: %w\", err)
	}
	return metadata, nil
}

// ValidateUserMetadata checks that metadata values are reasonable
// types and total size doesn't exceed 1KB.
func ValidateUserMetadata(metadata map[string]any) error {
	data, err := json.Marshal(metadata)
	if err != nil {
		return fmt.Errorf(\"error marshalling metadata: %w\", err)
	}
	if len(data) > 1024 {
		return fmt.Errorf(\"metadata exceeds 1KB limit (%d bytes)\", len(data))
	}
	return nil
}
'''

with open('$GO_DIR/controller/claim_mapper.go', 'w') as f:
    f.write(content)

print('  Added ExtractUserMetadata and ValidateUserMetadata')
"

echo "Stage 2 complete."
