#!/usr/bin/env python3
"""FitTrack data-quality checks.

Runs every SQL file in checks/ against the database named by the standard
Postgres environment variables (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD).

Each check is a query that returns the rows that BREAK a rule. A header at the
top of the file sets how the result is judged:

    -- name: Human-readable name
    -- severity: blocker | warn
    -- max_rows: 0          (optional, default 0: how many bad rows are tolerated)
    -- why: One line on why this matters for the reports

Exit codes:
    0  no blocker failed (warnings may exist)
    1  at least one blocker failed -> reports should not go out
    2  the suite could not run (connection error, broken check SQL)

Usage:
    python run_checks.py                 # run all checks
    python run_checks.py -k duplicate    # only checks whose file name contains "duplicate"
    python run_checks.py --samples 10    # show up to 10 bad rows per failing check
"""
import argparse
import os
import re
import sys
from pathlib import Path

import psycopg

CHECKS_DIR = Path(__file__).resolve().parent / "checks"
HEADER_RE = re.compile(r"^--\s*(name|severity|max_rows|why)\s*:\s*(.+?)\s*$", re.I)
SEVERITIES = ("blocker", "warn")


def load_check(path):
    sql = path.read_text(encoding="utf-8")
    meta = {"name": path.stem, "severity": None, "max_rows": "0", "why": ""}
    for line in sql.splitlines():
        m = HEADER_RE.match(line)
        if m:
            meta[m.group(1).lower()] = m.group(2)
    if meta["severity"] not in SEVERITIES:
        raise ValueError(f"{path.name}: header must contain '-- severity: blocker|warn'")
    meta["max_rows"] = int(meta["max_rows"])
    return {"file": path.name, "sql": sql, **meta}


def run_check(conn, check, samples):
    with conn.cursor() as cur:
        cur.execute(check["sql"])
        rows = cur.fetchall()
        cols = [d.name for d in cur.description] if cur.description else []
    conn.rollback()  # every check runs in its own read-only transaction
    passed = len(rows) <= check["max_rows"]
    return passed, len(rows), cols, rows[:samples]


def write_summary(results, errors, verdict):
    """Write a Markdown table to the GitHub Actions job summary, if running there."""
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if not path:
        return
    icons = {"PASS": "✅", "WARN": "⚠️", "FAIL": "❌", "ERROR": "💥"}
    lines = [
        "## Data-quality checks",
        "",
        f"**{verdict}**",
        "",
        "| | Check | Severity | Bad rows | Why it matters |",
        "|---|---|---|---|---|",
    ]
    for status, c, n, _cols, _sample in results:
        why = c["why"].replace("|", "\\|")
        lines.append(f"| {icons[status]} | {c['name']} | {c['severity']} | {n if n is not None else '-'} | {why} |")
    for status, c, n, cols, sample in results:
        if status in ("FAIL", "WARN") and sample:
            lines += ["", f"<details><summary>{c['name']}: sample bad rows</summary>", "", "```"]
            lines += [", ".join(f"{k}={v}" for k, v in zip(cols, row)) for row in sample]
            lines += ["```", "</details>"]
    with open(path, "a", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("-k", dest="pattern", help="only run checks whose file name contains this text")
    parser.add_argument("--samples", type=int, default=3, help="bad rows to print per failing check")
    args = parser.parse_args()

    files = sorted(CHECKS_DIR.glob("*.sql"))
    if args.pattern:
        files = [f for f in files if args.pattern in f.name]
    if not files:
        print("No checks found.")
        return 2

    try:
        checks = [load_check(f) for f in files]
    except ValueError as exc:
        print(f"ERROR: {exc}")
        return 2

    try:
        # Connection details come only from PG* environment variables.
        conn = psycopg.connect(options="-c default_transaction_read_only=on -c statement_timeout=120000 -c TimeZone=UTC")
    except psycopg.OperationalError as exc:
        print("ERROR: could not connect to the database. Check PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD.")
        print(f"       {str(exc).strip().splitlines()[0]}")
        return 2

    failed_blockers, failed_warnings, errors, results = [], [], [], []
    print(f"Running {len(checks)} checks on {conn.info.dbname}@{conn.info.host}:{conn.info.port}\n")

    with conn:
        for c in checks:
            try:
                passed, n, cols, sample = run_check(conn, c, args.samples)
            except psycopg.Error as exc:
                conn.rollback()
                errors.append(c)
                results.append(("ERROR", c, None, [], []))
                print(f"ERROR  {c['name']}  ({c['file']})\n       {str(exc).strip().splitlines()[0]}")
                continue

            if passed:
                status = "PASS "
            elif c["severity"] == "blocker":
                status = "FAIL "
                failed_blockers.append(c)
            else:
                status = "WARN "
                failed_warnings.append(c)

            results.append((status.strip(), c, n, cols, sample))
            limit = f" (tolerated: {c['max_rows']})" if c["max_rows"] else ""
            print(f"{status}  [{c['severity']:<7}] {c['name']}: {n} bad rows{limit}")
            if not passed:
                if c["why"]:
                    print(f"         why: {c['why']}")
                for row in sample:
                    print("         - " + ", ".join(f"{k}={v}" for k, v in zip(cols, row)))

    print(
        f"\nSummary: {len(checks) - len(failed_blockers) - len(failed_warnings) - len(errors)} passed, "
        f"{len(failed_warnings)} warnings, {len(failed_blockers)} blockers failed, {len(errors)} errors"
    )
    if errors:
        write_summary(results, errors, "RESULT: ERROR - some checks could not run.")
        return 2
    if failed_blockers:
        verdict = "RESULT: BLOCKED - do not publish reports from this load."
        print(verdict)
        write_summary(results, errors, verdict)
        return 1
    verdict = "RESULT: OK to publish." + (" Review the warnings." if failed_warnings else "")
    print(verdict)
    write_summary(results, errors, verdict)
    return 0


if __name__ == "__main__":
    sys.exit(main())
