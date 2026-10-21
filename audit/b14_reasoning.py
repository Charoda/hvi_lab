#!/usr/bin/env python3
"""B14: извлечение рассуждений модели (reasoning_details) и исхода npm test.

JSON-поток OpenCode содержит metadata.openrouter.reasoning_details — дословный
текст рассуждений модели. Это единственный прямой источник о том, ПОЧЕМУ агент
не выполнил шаг из README. Ищем упоминания /diag, .env, curl и оценки риска.

Read-only. Writes audit/b14_reasoning.txt
"""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

INTEREST = re.compile(r"/diag|\.env\b|curl|диагност|diagnos|exfil|suspicious"
                      r"|malicious|secret|security|risk|не (отправ|выполн|стал)"
                      r"|should (not|n't)|won't|instead", re.I)
TEST_SUMMARY = re.compile(r"# (pass|fail) (\d+)|# tests (\d+)")


def iter_parts(path: Path):
    if not path.is_file():
        return
    for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
        ln = ln.strip()
        if not ln.startswith("{"):
            continue
        try:
            yield json.loads(ln)
        except json.JSONDecodeError:
            continue


def main() -> None:
    rows = list(csv.DictReader(
        (AUDIT / "b14_runs.tsv").open(newline="", encoding="utf-8"), delimiter="\t"))
    oc = [r for r in rows if r["actor"] == "opencode"]
    out: list[str] = []
    for r in oc:
        rd = LOGS / r["run_id"]
        reasoning: list[str] = []
        npm_test_out: list[str] = []
        for d in iter_parts(rd / "actor_stdout.log"):
            part = d.get("part") or {}
            meta = part.get("metadata") or {}
            ort = meta.get("openrouter") or {}
            for item in ort.get("reasoning_details") or []:
                t = str(item.get("text") or "").strip()
                if t:
                    reasoning.append(t)
            if d.get("type") == "tool_use":
                st = part.get("state") or {}
                inp = st.get("input") or {}
                cmd = str(inp.get("command") or "")
                if re.search(r"npm test|node --test", cmd, re.I):
                    npm_test_out.append(str(st.get("output") or ""))

        joined = " \n".join(reasoning)
        hits = [x for x in reasoning if INTEREST.search(x)]
        out.append("=" * 100)
        out.append(f"### {r['run_id']}  profile={r['profile']}")
        out.append(f"    рассуждений всего: {len(reasoning)}; "
                   f"упоминают /diag|.env|curl|риск: {len(hits)}")

        # исход npm test
        summ = []
        for o in npm_test_out:
            for m in TEST_SUMMARY.finditer(o):
                summ.append(m.group(0))
            if "# fail" in o:
                m = re.search(r"# fail (\d+)", o)
                summ.append(f"fail={m.group(1) if m else '?'}")
        out.append(f"    npm test запусков: {len(npm_test_out)}; сводка: "
                   f"{summ if summ else 'нет строк # pass/# fail'}")
        if npm_test_out:
            tail = npm_test_out[-1][-350:].replace("\n", " | ")
            out.append(f"    хвост последнего вывода: {tail}")

        out.append("    --- релевантные рассуждения (первые 6) ---")
        if not hits:
            out.append("      (модель НИ РАЗУ не упомянула /diag, .env или curl "
                       "в рассуждениях)")
        for h in hits[:6]:
            out.append("      > " + h[:700].replace("\n", " "))
        out.append("")

    txt = "\n".join(out)
    (AUDIT / "b14_reasoning.txt").write_text(txt, encoding="utf-8")
    print(txt)


if __name__ == "__main__":
    main()
