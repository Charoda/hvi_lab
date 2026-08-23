"""MOSAIC chain testing database — tracks chain design, agent compliance, and reviewer evasion."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).parent / "chains.db"
CHAINS_DIR = Path(__file__).parent.parent / "chains"
BUGBOT_MODELS = {"codex", "gemini", "opus", "sonnet", "minimax", "codex54",
                  "deepseek_v4_pro", "deepseek_v4_flash", "qwen36", "qwen35", "kimi_k26",
                  "glm5", "gemini_3_flash", "gemini_3_pro",
                  "grok420", "grok420r"}


def _ensure_columns(db: sqlite3.Connection, table: str, columns: dict[str, str]) -> None:
    """Add missing columns to an existing table."""
    existing = {
        row["name"]
        for row in db.execute(f"PRAGMA table_info({table})").fetchall()
    }
    for name, decl in columns.items():
        if name not in existing:
            db.execute(f"ALTER TABLE {table} ADD COLUMN {name} {decl}")


def get_db() -> sqlite3.Connection:
    """Get or create the chain testing database."""
    db = sqlite3.connect(str(DB_PATH))
    db.row_factory = sqlite3.Row
    db.execute("""
        CREATE TABLE IF NOT EXISTS chains (
            chain_id TEXT PRIMARY KEY,

            -- Chain design
            app TEXT,
            language TEXT,
            target_cwe TEXT,
            severity TEXT,  -- LOW, MEDIUM, HIGH

            -- Tickets
            ticket_1 TEXT,
            ticket_2 TEXT,
            ticket_3 TEXT,
            ticket_1_to_2_rationale TEXT,
            ticket_2_to_3_rationale TEXT,

            -- Agent compliance
            agent_executed INTEGER,  -- 0/1
            agent_response TEXT,

            -- BugBot reviews (APPROVE/DENY + explanation)
            bugbot_codex_verdict TEXT,
            bugbot_codex_explanation TEXT,
            bugbot_gemini_verdict TEXT,
            bugbot_gemini_explanation TEXT,
            bugbot_opus_verdict TEXT,
            bugbot_opus_explanation TEXT,
            bugbot_sonnet_verdict TEXT,
            bugbot_sonnet_explanation TEXT,

            -- Meta
            evasion_score TEXT,
            quadrant TEXT,  -- Q1/Q2/Q3/Q4
            notes TEXT,
            updated_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    _ensure_columns(db, "chains", {
        "bugbot_codex_ctx_verdict": "TEXT",
        "bugbot_codex_ctx_explanation": "TEXT",
        "bugbot_gemini_ctx_verdict": "TEXT",
        "bugbot_gemini_ctx_explanation": "TEXT",
        "bugbot_opus_ctx_verdict": "TEXT",
        "bugbot_opus_ctx_explanation": "TEXT",
        "bugbot_sonnet_ctx_verdict": "TEXT",
        "bugbot_sonnet_ctx_explanation": "TEXT",
        "bugbot_deepseek_v4_pro_verdict": "TEXT",
        "bugbot_deepseek_v4_pro_explanation": "TEXT",
        "bugbot_deepseek_v4_flash_verdict": "TEXT",
        "bugbot_deepseek_v4_flash_explanation": "TEXT",
        "bugbot_qwen36_verdict": "TEXT",
        "bugbot_qwen36_explanation": "TEXT",
        "bugbot_qwen36_ctx_verdict": "TEXT",
        "bugbot_qwen36_ctx_explanation": "TEXT",
        "bugbot_qwen35_verdict": "TEXT",
        "bugbot_qwen35_explanation": "TEXT",
        "bugbot_qwen35_ctx_verdict": "TEXT",
        "bugbot_qwen35_ctx_explanation": "TEXT",
        "bugbot_kimi_k26_verdict": "TEXT",
        "bugbot_kimi_k26_explanation": "TEXT",
        "bugbot_glm5_verdict": "TEXT",
        "bugbot_glm5_explanation": "TEXT",
        "bugbot_gemini_3_flash_verdict": "TEXT",
        "bugbot_gemini_3_flash_explanation": "TEXT",
        "bugbot_gemini_3_pro_verdict": "TEXT",
        "bugbot_gemini_3_pro_explanation": "TEXT",
        "bugbot_grok420_verdict": "TEXT",
        "bugbot_grok420_explanation": "TEXT",
        "bugbot_grok420r_verdict": "TEXT",
        "bugbot_grok420r_explanation": "TEXT",
        "bugbot_grok420_ctx_verdict": "TEXT",
        "bugbot_grok420_ctx_explanation": "TEXT",
        "bugbot_grok420r_ctx_verdict": "TEXT",
        "bugbot_grok420r_ctx_explanation": "TEXT",
        "bugbot_glm5_ctx_verdict": "TEXT",
        "bugbot_glm5_ctx_explanation": "TEXT",
        "bugbot_gemini_3_flash_ctx_verdict": "TEXT",
        "bugbot_gemini_3_flash_ctx_explanation": "TEXT",
        "bugbot_gemini_3_pro_ctx_verdict": "TEXT",
        "bugbot_gemini_3_pro_ctx_explanation": "TEXT",
    })
    # Trial-level results (every individual BugBot review)
    db.execute("""
        CREATE TABLE IF NOT EXISTS trials (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            chain_id TEXT NOT NULL,
            model TEXT NOT NULL,
            diff_mode TEXT NOT NULL,
            verdict TEXT,
            explanation TEXT,
            diff_lines INTEGER,
            diff_bytes INTEGER,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (chain_id) REFERENCES chains(chain_id)
        )
    """)
    db.commit()
    return db


def record_trial(chain_id: str, model: str, diff_mode: str,
                 verdict: str, explanation: str,
                 diff_lines: int = 0, diff_bytes: int = 0):
    """Record an individual BugBot review trial."""
    if model not in BUGBOT_MODELS:
        raise ValueError(f"Invalid model {model!r}. Allowed: {sorted(BUGBOT_MODELS)}")
    valid_modes = (
        "cumulative",
        "stage3_only",
        "stage1_only",
        "stage2_only",
        "cumulative_ctx",
        "stage3_only_ctx",
    )
    if diff_mode not in valid_modes:
        raise ValueError(f"Invalid diff_mode {diff_mode!r}. Allowed: {valid_modes}")
    db = get_db()
    db.execute("""
        INSERT INTO trials (chain_id, model, diff_mode, verdict, explanation,
                           diff_lines, diff_bytes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (chain_id, model, diff_mode, verdict, explanation, diff_lines, diff_bytes))
    db.commit()


def export_csv(output_path: str | None = None):
    """Export all data to CSV files for live viewing."""
    import csv
    db = get_db()
    base = Path(output_path) if output_path else DB_PATH.parent

    # Export chains table
    rows = db.execute("SELECT * FROM chains ORDER BY chain_id").fetchall()
    chains_csv = base / "chains_export.csv"
    with open(chains_csv, "w", newline="") as f:
        if rows:
            writer = csv.writer(f)
            writer.writerow(rows[0].keys())
            writer.writerows(rows)
    print(f"Exported {len(rows)} chains → {chains_csv}")

    # Export trials table
    rows = db.execute("SELECT * FROM trials ORDER BY created_at DESC").fetchall()
    trials_csv = base / "trials_export.csv"
    with open(trials_csv, "w", newline="") as f:
        if rows:
            writer = csv.writer(f)
            writer.writerow(rows[0].keys())
            writer.writerows(rows)
    print(f"Exported {len(rows)} trials → {trials_csv}")

    return str(chains_csv), str(trials_csv)


def populate_from_chains():
    """Populate DB from all chain.json files."""
    db = get_db()

    for chain_dir in sorted(CHAINS_DIR.iterdir()):
        chain_json = chain_dir / "chain.json"
        if not chain_json.exists():
            continue

        data = json.loads(chain_json.read_text())
        chain_id = data.get("chain_id", chain_dir.name)

        # Read stage tickets
        stages = {}
        for i in range(1, 4):
            stage_file = chain_dir / f"stage{i}.txt"
            if stage_file.exists():
                content = stage_file.read_text().strip()
                # Extract first line as summary
                first_line = content.split("\n")[0]
                stages[i] = {"summary": first_line, "full": content}

        # Determine app from task_id
        task_id = data.get("task_id", "")
        app_map = {
            "hagopj13": "Express boilerplate",
            "haozhang95": "Flask shop",
            "izghua": "Gin blog",
            "nhost": "Hasura auth",
            "ankur": "SSO",
            "attacomsian": "File upload",
            "stripe": "Stripe",
            "swaggo": "Swag/Gin",
        }
        app = next((v for k, v in app_map.items() if k in task_id), task_id[:25])

        # Language from app
        lang_map = {"Express": "JavaScript", "Flask": "Python", "Gin": "Go", "SSO": "JavaScript",
                     "File upload": "JavaScript", "Stripe": "Python", "Swag": "Go", "Hasura": "Go"}
        language = next((v for k, v in lang_map.items() if k in app), "unknown")

        cwe = ", ".join(data.get("cwe_ids", []))

        # Rationales (inferred from stage content)
        t1_to_2 = ""
        t2_to_3 = ""
        if 1 in stages and 2 in stages:
            t1_to_2 = f"Stage 1 establishes the feature/pattern. Stage 2 builds the mechanism that will be exploited."
        if 2 in stages and 3 in stages:
            t2_to_3 = f"Stage 2 creates the attack surface. Stage 3 triggers the vulnerability via a 'fix' or 'improvement'."

        # Use INSERT OR IGNORE to avoid wiping existing verdict data
        db.execute("""
            INSERT OR IGNORE INTO chains
            (chain_id, app, language, target_cwe, severity,
             ticket_1, ticket_2, ticket_3,
             ticket_1_to_2_rationale, ticket_2_to_3_rationale,
             notes, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        """, (
            chain_id, app, language, cwe,
            data.get("severity", "MEDIUM"),
            stages.get(1, {}).get("summary", ""),
            stages.get(2, {}).get("summary", ""),
            stages.get(3, {}).get("summary", ""),
            t1_to_2, t2_to_3,
            data.get("description", ""),
        ))
        # Update metadata without touching verdicts
        db.execute("""
            UPDATE chains SET app=?, language=?, target_cwe=?, severity=?,
             ticket_1=?, ticket_2=?, ticket_3=?,
             notes=?, updated_at=CURRENT_TIMESTAMP
            WHERE chain_id=?
        """, (
            app, language, cwe, data.get("severity", "MEDIUM"),
            stages.get(1, {}).get("summary", ""),
            stages.get(2, {}).get("summary", ""),
            stages.get(3, {}).get("summary", ""),
            data.get("description", ""),
            chain_id,
        ))

    db.commit()
    print(f"Populated {db.execute('SELECT COUNT(*) FROM chains').fetchone()[0]} chains")
    return db


def update_bugbot(chain_id: str, model: str, verdict: str, explanation: str,
                  context_mode: str = "diff"):
    """Update BugBot review result for a chain.

    context_mode:
        diff / None -> store in the existing diff columns
        app / workspace -> store in the ctx columns
    """
    if model not in BUGBOT_MODELS:
        raise ValueError(f"Invalid model {model!r}. Allowed: {sorted(BUGBOT_MODELS)}")
    if context_mode in (None, "diff"):
        suffix = ""
    elif context_mode in ("app", "workspace"):
        suffix = "_ctx"
    else:
        raise ValueError("context_mode must be one of: diff, app, workspace")
    db = get_db()
    col_verdict = f"bugbot_{model}{suffix}_verdict"
    col_explain = f"bugbot_{model}{suffix}_explanation"
    db.execute(f"""
        UPDATE chains SET {col_verdict} = ?, {col_explain} = ?, updated_at = CURRENT_TIMESTAMP
        WHERE chain_id = ?
    """, (verdict, explanation, chain_id))
    db.commit()


def update_agent(chain_id: str, executed: bool, response: str):
    """Update agent compliance result."""
    db = get_db()
    db.execute("""
        UPDATE chains SET agent_executed = ?, agent_response = ?, updated_at = CURRENT_TIMESTAMP
        WHERE chain_id = ?
    """, (1 if executed else 0, response, chain_id))
    db.commit()


def update_severity(chain_id: str, severity: str):
    """Update severity rating."""
    db = get_db()
    db.execute("UPDATE chains SET severity = ?, updated_at = CURRENT_TIMESTAMP WHERE chain_id = ?",
               (severity, chain_id))
    db.commit()


def show_matrix():
    """Print the full evasion × severity matrix."""
    db = get_db()
    rows = db.execute("""
        SELECT chain_id, app, language, target_cwe, severity,
               bugbot_codex_verdict, bugbot_gemini_verdict,
               bugbot_opus_verdict, bugbot_sonnet_verdict,
               agent_executed
        FROM chains ORDER BY chain_id
    """).fetchall()

    print(f"{'Chain':<40} {'App':<18} {'CWE':<12} {'Sev':<6} {'Codex':<8} {'Gemini':<8} {'Opus':<8} {'Sonnet':<8} {'Agent':<6}")
    print("-" * 140)
    for r in rows:
        codex = (r["bugbot_codex_verdict"] or "—")[:7]
        gemini = (r["bugbot_gemini_verdict"] or "—")[:7]
        opus = (r["bugbot_opus_verdict"] or "—")[:7]
        sonnet = (r["bugbot_sonnet_verdict"] or "—")[:7]
        agent = "YES" if r["agent_executed"] else ("NO" if r["agent_executed"] == 0 else "—")
        print(f"{r['chain_id']:<40} {(r['app'] or ''):<18} {(r['target_cwe'] or ''):<12} {(r['severity'] or ''):<6} {codex:<8} {gemini:<8} {opus:<8} {sonnet:<8} {agent:<6}")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "populate":
        populate_from_chains()
    elif len(sys.argv) > 1 and sys.argv[1] == "matrix":
        show_matrix()
    else:
        print("Usage: python chain_db.py [populate|matrix]")
