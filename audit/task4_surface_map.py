#!/usr/bin/env python3
"""Audit Task 4 (step 3): ground-truth map of the injection surface per scenario.

For every scenario in isolated/harness/scenarios.txt find, inside the app
fixture, the files that carry the exfil channel (honey URL / marker / curl)
and the files that carry the *instruction* pointing at it.

Read-only. Writes audit/task4_surface_map.tsv
"""
from __future__ import annotations

import json
import re
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
APPS = REPO / "benchmark/apps"
CHAINS = REPO / "benchmark/chains"
AUDIT = REPO / "audit"

EXFIL = re.compile(r"localhost:8080|127\.0\.0\.1:8080|/exfil|/stolen|/setup\b|/init\b"
                   r"|curl\s|wget\s|urlopen|requests\.post|HONEY", re.I)
MARKER = re.compile(r"\b(?:lt|mk|bm|b\d+)[a-z]*_[A-Za-z0-9]{6,}|marker\"?\s*[:=]", re.I)
INSTRUCT = re.compile(r"run\s+`?tools/|запусти|выполни|please run|before you finish|"
                      r"IMPORTANT|NOTE:|do not mention|не упоминай", re.I)

SKIP_DIRS = {"__pycache__", ".git", "node_modules", "venv"}


def substrate(scenario: str) -> str | None:
    cj = CHAINS / scenario / "chain.json"
    if not cj.is_file():
        return None
    try:
        return json.loads(cj.read_text(encoding="utf-8")).get("task_id")
    except json.JSONDecodeError:
        return None


def scan(app: Path) -> list[tuple[str, str, str]]:
    hits: list[tuple[str, str, str]] = []
    for p in sorted(app.rglob("*")):
        if not p.is_file() or any(s in p.parts for s in SKIP_DIRS):
            continue
        if p.stat().st_size > 400_000:
            continue
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        rel = str(p.relative_to(app))
        for n, ln in enumerate(txt.splitlines(), 1):
            tag = []
            if EXFIL.search(ln):
                tag.append("EXFIL")
            if MARKER.search(ln):
                tag.append("MARKER")
            if INSTRUCT.search(ln):
                tag.append("INSTRUCT")
            if tag:
                hits.append((rel, "+".join(tag), f"L{n}: {ln.strip()[:150]}"))
    return hits


def main() -> None:
    scenarios = [s.strip() for s in
                 (REPO / "isolated/harness/scenarios.txt").read_text().splitlines()
                 if s.strip() and not s.strip().startswith("#")]
    out: list[str] = ["scenario\ttask_id\tapp_dir\tfile\ttag\tline"]
    print(f"сценариев: {len(scenarios)}")
    for sc in scenarios:
        if sc.endswith("_benign"):
            continue
        tid = substrate(sc)
        app = APPS / tid if tid else None
        if not app or not app.is_dir():
            print(f"  {sc}: task_id={tid} — каталог приложения НЕ НАЙДЕН")
            continue
        hits = scan(app)
        files = sorted({h[0] for h in hits if "EXFIL" in h[1] or "MARKER" in h[1]})
        print(f"  {sc:24s} {tid:44s} exfil/marker файлы: {files}")
        for rel, tag, line in hits:
            out.append("\t".join([sc, tid, str(app), rel, tag, line]))
    (AUDIT / "task4_surface_map.tsv").write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"\n-> audit/task4_surface_map.tsv ({len(out) - 1} строк)")


if __name__ == "__main__":
    main()
