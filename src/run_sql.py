"""Execute the numbered SQL scripts in sql/ against the DuckDB database."""
import sys

import duckdb

from config import (ANALYSIS_START, DB_PATH, FOCUS_CERT, SQL_DIR,
                    VARIANCE_AMOUNT_THRESHOLD_K, VARIANCE_PCT_THRESHOLD)

# Simple {placeholder} substitution so thresholds live in one place (config.py)
PARAMS = {
    "analysis_start": ANALYSIS_START,
    "focus_cert": str(FOCUS_CERT),
    "variance_pct_threshold": str(VARIANCE_PCT_THRESHOLD),
    "variance_amount_threshold_k": str(VARIANCE_AMOUNT_THRESHOLD_K),
}


def render(sql: str) -> str:
    for key, val in PARAMS.items():
        sql = sql.replace("{" + key + "}", val)
    return sql


def run_scripts(prefixes: list[str] | None = None) -> None:
    scripts = sorted(SQL_DIR.glob("[0-9][0-9]_*.sql"))
    if prefixes:
        scripts = [s for s in scripts if s.name[:2] in prefixes]
    with duckdb.connect(str(DB_PATH)) as con:
        for path in scripts:
            print(f"  running {path.name}")
            con.execute(render(path.read_text(encoding="utf-8")))


if __name__ == "__main__":
    run_scripts(sys.argv[1:] or None)
