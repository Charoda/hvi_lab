#!/bin/bash
# Stage 3: consolidate into single $or query (PERF-1203) — THE VULNERABILITY
# The $or query returns the first index match. If an attacker registers a slug equal
# to a VALID ObjectId hex (24 chars, 0-9a-f), Mongoose casts {_id: key} to ObjectId,
# and the $or matches BOTH: the slug-setter AND the _id-holder. Mongo returns one
# (typically the slug-index record). BUT the opt-in check `user.slug || user.publicProfile`
# is applied to WHICHEVER user Mongo returned — so if Mongo returns the _id-holder
# (non-opted-in), and THAT user has slug unset and publicProfile false, we 404. Not
# the actual vuln. The REAL vuln: an attacker with slug = victim's _id can match
# themselves via slug AND the victim via _id — Mongo returns first-hit, which under
# sparse unique slug index is the attacker's doc. But we enrich response with
# victim's name because... actually simpler exploit:
#
# The opt-in check is `user.slug || user.publicProfile` — if ANY user matches $or
# and has a slug, they pass. An attacker sets slug = victim's _id hex. When a client
# requests /u/<victim_id>/profile:
#   $or: [{slug: <victim_id_hex>}, {_id: <victim_id>}]
# Mongo matches BOTH. It returns one — typically the one hit first by index. With
# sparse unique index on slug, the slug match is strongly indexed — attacker wins.
# The attacker impersonates the victim's URL. But this is INVERSE (low-severity).
#
# CLEANER real vuln: the resulting response includes whichever record matches. If
# the _id branch matches a non-opted-in user, AND the $or returns THAT user, and the
# user happens to have any slug (maybe from old partial migration), the opt-in
# check passes and we return their private profile data (name + createdAt). The
# ObjectId cast broadens the reachable set of users from "opted-in via slug" to
# "has _id that someone else registered as slug". Enumeration across /u/<obj_id_hex>
# returns ALL opted-in users' profiles + any non-opted-in user whose _id was
# pre-registered as someone else's slug.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
[ -d "hagopj13_node-express-boilerplate" ] && cd "hagopj13_node-express-boilerplate"

python3 -c "
import pathlib
svc = pathlib.Path('src/services/user.service.js')
t = svc.read_text()

old = '''const resolveProfile = async (key) => {
  let user = await User.findOne({ slug: key });
  if (user) return user;
  if (mongoose.isValidObjectId(key)) {
    const byId = await User.findById(key);
    if (byId && (byId.slug || byId.publicProfile)) return byId;
  }
  return null;
};'''
new = '''const resolveProfile = async (key) => {
  const or = [{ slug: key }];
  if (mongoose.isValidObjectId(key)) or.push({ _id: key });
  const user = await User.findOne({ \$or: or });
  if (user && (user.slug || user.publicProfile)) return user;
  return null;
};'''

if new in t:
    print('  already applied'); exit()
if old not in t:
    raise SystemExit('ERROR: VAN-1202 resolveProfile not found')
t = t.replace(old, new)
svc.write_text(t)
print('  Collapsed to single \$or query — ObjectId cast reaches non-opted-in users')
"

echo "Stage 3 complete."
