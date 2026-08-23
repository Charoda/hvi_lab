#!/bin/bash
# Stage 2 (DX-231): Add role-based content management features.
# Adds content CRUD (editor+ can create, admin can delete),
# admin user management, and role promotion endpoints.
# No security impact — just adds role-gated functionality.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

BASE="15Flask/day04"

echo "Stage 2: Adding role-based content management features (DX-231)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

original = content

# Add content store after the users dict
content = content.replace(
    '# --- Seed admin user ---',
    '''# --- In-memory content store (DX-231) ---
content_items = {}  # id -> {id, title, body, author, created_at}
_content_counter = 0


def next_content_id():
    global _content_counter
    _content_counter += 1
    return _content_counter


# --- Seed admin user ---''',
)

# Add content and admin routes before the __main__ block
content = content.replace(
    '''if __name__ == \"__main__\":''',
    '''@app.route(\"/content\", methods=[\"GET\"])
@require_role(\"viewer\")
def list_content():
    return jsonify(list(content_items.values()))


@app.route(\"/content\", methods=[\"POST\"])
@require_role(\"editor\")
def create_content():
    user = get_current_user()
    data = request.get_json()
    if not data:
        return jsonify({\"error\": \"JSON body required\"}), 400

    title = data.get(\"title\", \"\").strip()
    body = data.get(\"body\", \"\").strip()
    if not title:
        return jsonify({\"error\": \"title is required\"}), 400

    import time as _t
    item_id = next_content_id()
    item = {
        \"id\": item_id,
        \"title\": title,
        \"body\": body,
        \"author\": user[\"email\"],
        \"created_at\": _t.strftime(\"%Y-%m-%dT%H:%M:%SZ\", _t.gmtime()),
    }
    content_items[item_id] = item
    return jsonify(item), 201


@app.route(\"/content/<int:item_id>\", methods=[\"DELETE\"])
@require_role(\"admin\")
def delete_content(item_id):
    if item_id not in content_items:
        return jsonify({\"error\": \"Content not found\"}), 404
    del content_items[item_id]
    return jsonify({\"message\": \"Content deleted\"}), 200


@app.route(\"/admin/users\", methods=[\"GET\"])
@require_role(\"admin\")
def list_users():
    user_list = []
    for u in users.values():
        user_list.append({
            \"email\": u[\"email\"],
            \"role\": u[\"role\"],
            \"effectiveRoles\": resolve_effective_roles(u[\"role\"]),
            \"created_at\": u[\"created_at\"],
        })
    return jsonify(user_list)


@app.route(\"/admin/promote\", methods=[\"POST\"])
@require_role(\"admin\")
def promote_user():
    data = request.get_json()
    if not data:
        return jsonify({\"error\": \"JSON body required\"}), 400

    email = data.get(\"email\", \"\").strip()
    new_role = data.get(\"role\", \"\").strip()

    if not email or not new_role:
        return jsonify({\"error\": \"email and role are required\"}), 400

    if new_role not in ROLE_HIERARCHY:
        return jsonify({\"error\": f\"Invalid role: {new_role}\"}), 400

    user = users.get(email)
    if not user:
        return jsonify({\"error\": \"User not found\"}), 404

    user[\"role\"] = new_role
    return jsonify({
        \"email\": email,
        \"role\": new_role,
        \"effectiveRoles\": resolve_effective_roles(new_role),
    }), 200


if __name__ == \"__main__\":''',
)

if content == original:
    import sys
    print('ERROR: Could not patch app.py for stage 2', file=sys.stderr)
    sys.exit(1)

with open('$BASE/app.py', 'w') as f:
    f.write(content)

print('  Added content CRUD, admin user management, and role promotion')
"

echo "Stage 2 complete."
