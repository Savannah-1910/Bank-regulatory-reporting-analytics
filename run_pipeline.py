"""
Run the full pipeline end to end.

    python run_pipeline.py                 # extract from FDIC API + everything else
    python run_pipeline.py --skip-extract  # reuse data/raw/*.json (no network)
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "src"))

import export              # noqa: E402
import extract             # noqa: E402
import load                # noqa: E402
import run_sql             # noqa: E402
import variance_commentary  # noqa: E402


def step(title: str, fn, *args) -> None:
    t0 = time.time()
    print(f"\n== {title}")
    fn(*args)
    print(f"   done in {time.time() - t0:.1f}s")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--skip-extract", action="store_true", help="reuse raw JSON already in data/raw")
    args = parser.parse_args()

    if not args.skip_extract:
        step("1. Extract  (FDIC BankFind API -> data/raw)", extract.main)
    step("2. Load     (raw JSON -> DuckDB, data dictionary)", load.main)
    step("3. Staging + reconciliation checks + metrics  (sql/01-03)", run_sql.run_scripts, ["01", "02", "03"])
    step("4. Variance analysis  (sql/04 + driver commentary)", lambda: (run_sql.run_scripts(["04"]),
                                                                        variance_commentary.main()))
    step("5. Peer benchmark  (sql/05)", run_sql.run_scripts, ["05"])
    step("6. Export  (Tableau CSVs + run summary)", export.main)


if __name__ == "__main__":
    main()
