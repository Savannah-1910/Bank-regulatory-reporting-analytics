"""
Step 1b - Load raw JSON into DuckDB and build the data dictionary.

Tables created here (everything else is built by the SQL scripts):
  raw_financials   one row per bank x quarter, one column per Call Report field ($ thousands)
  ref_bank         bank universe with short name, peer group, HQ, holding company
  ref_field        data dictionary for every extracted field
"""
import json

import duckdb
import pandas as pd
import yaml

from config import (BANK_LABELS, DB_PATH, DOCS_DIR, FIELDS, FOCUS_CERT,
                    RAW_DIR)


def load_financials(con: duckdb.DuckDBPyConnection) -> int:
    rows = json.loads((RAW_DIR / "financials.json").read_text())
    df = pd.DataFrame(rows)
    df["CERT"] = df["CERT"].astype(int)
    df["REPDTE"] = pd.to_datetime(df["REPDTE"], format="%Y%m%d").dt.date
    for code in FIELDS:
        if code not in df.columns:          # field absent for every bank-quarter
            df[code] = None
        df[code] = pd.to_numeric(df[code], errors="coerce").astype("float64")
    df = df[["CERT", "REPDTE", "NAMEFULL", *FIELDS]]
    con.execute("CREATE OR REPLACE TABLE raw_financials AS SELECT * FROM df")
    return len(df)


def load_banks(con: duckdb.DuckDBPyConnection) -> int:
    universe = pd.DataFrame(json.loads((RAW_DIR / "universe.json").read_text()))
    inst = pd.DataFrame(json.loads((RAW_DIR / "institutions.json").read_text()))
    inst["CERT"] = inst["CERT"].astype(int)
    banks = universe.merge(inst, on="CERT", how="left")
    banks["short_name"] = banks["CERT"].map(lambda c: BANK_LABELS.get(c, (None, None))[0])
    banks["peer_group"] = banks["CERT"].map(lambda c: BANK_LABELS.get(c, (None, "Other"))[1])
    banks["short_name"] = banks["short_name"].fillna(banks["NAMEFULL"].str.split().str[0])
    banks["is_focus_bank"] = banks["CERT"] == FOCUS_CERT
    ref_bank = banks.rename(columns={
        "CERT": "cert", "NAMEFULL": "bank_name", "ASSET_RANK": "asset_rank",
        "CITY": "hq_city", "STALP": "hq_state", "NAMEHCR": "holding_company",
        "BKCLASS": "charter_class", "REGAGNT": "primary_regulator",
    })[["cert", "bank_name", "short_name", "peer_group", "asset_rank", "hq_city",
        "hq_state", "holding_company", "charter_class", "primary_regulator", "is_focus_bank"]]
    con.execute("CREATE OR REPLACE TABLE ref_bank AS SELECT * FROM ref_bank")
    return len(ref_bank)


def load_structure_events(con: duckdb.DuckDBPyConnection) -> int:
    """Mergers / failed-bank acquisitions / reorganizations, mapped to the quarter they hit."""
    hist = pd.DataFrame(json.loads((RAW_DIR / "structure_history.json").read_text()))
    if hist.empty:
        hist = pd.DataFrame(columns=["CERT", "EFFDATE", "CHANGECODE", "CHANGECODE_DESC",
                                     "OUT_INSTNAME", "OUT_CERT"])
    hist["effective_date"] = pd.to_datetime(hist["EFFDATE"]).dt.date
    hist["quarter_end"] = (pd.to_datetime(hist["EFFDATE"]) + pd.offsets.QuarterEnd(0)).dt.date
    ev = hist.rename(columns={"CERT": "cert", "CHANGECODE": "change_code",
                              "CHANGECODE_DESC": "change_desc",
                              "OUT_INSTNAME": "counterparty_name", "OUT_CERT": "counterparty_cert"})
    ev = ev[["cert", "effective_date", "quarter_end", "change_code", "change_desc",
             "counterparty_name", "counterparty_cert"]]
    ev["event_label"] = ev.apply(
        lambda r: (f"merged {r.counterparty_name} on {r.effective_date}"
                   if r.change_code == 810 else
                   f"acquired failed bank {r.counterparty_name} on {r.effective_date}"
                   if r.change_code == 811 else
                   f"corporate reorganization on {r.effective_date}"), axis=1)
    con.execute("CREATE OR REPLACE TABLE ref_structure_event AS SELECT * FROM ev")
    return len(ev)


def build_data_dictionary(con: duckdb.DuckDBPyConnection) -> pd.DataFrame:
    """Combine our business names with FDIC's official titles/descriptions."""
    official = {}
    yaml_path = RAW_DIR / "risview_properties.yaml"
    if yaml_path.exists():
        spec = yaml.safe_load(yaml_path.read_text(encoding="utf-8"))
        official = spec["properties"]["data"]["properties"]

    period_desc = {
        "point_in_time": "Balance as of quarter end",
        "ytd": "Year-to-date flow; de-cumulated to quarterly in stg_income_quarterly",
        "quarterly": "Single-quarter flow published by FDIC; used as control total",
        "ratio_pct": "Ratio published by FDIC (percent); used to cross-check recomputed metrics",
    }
    rows = []
    for code, (name, statement, category, period_type) in FIELDS.items():
        meta = official.get(code, {}) or {}
        rows.append({
            "field_code": code,
            "business_name": name,
            "statement": statement,
            "category": category,
            "period_type": period_type,
            "period_note": period_desc[period_type],
            "unit": "percent" if period_type == "ratio_pct" else "USD thousands",
            "fdic_title": (meta.get("title") or "").strip(),
            "fdic_description": " ".join((meta.get("description") or "").split()),
        })
    dd = pd.DataFrame(rows)
    con.execute("CREATE OR REPLACE TABLE ref_field AS SELECT * FROM dd")

    DOCS_DIR.mkdir(parents=True, exist_ok=True)
    dd.to_csv(DOCS_DIR / "data_dictionary.csv", index=False)

    lines = ["# Data Dictionary - FDIC Call Report fields", "",
             "Source: FDIC BankFind Suite API (`/financials`). "
             "Dollar amounts are in **USD thousands** as published by FDIC.", "",
             f"{len(dd)} fields extracted. `period_type` matters: income-statement fields in the "
             "Call Report are **year-to-date**, so they must be de-cumulated before any "
             "quarter-over-quarter comparison.", ""]
    for statement, grp in dd.groupby("statement", sort=False):
        lines += [f"## {statement}", "",
                  "| Field | Business name | Category | Period type | FDIC title |",
                  "|---|---|---|---|---|"]
        for r in grp.itertuples():
            lines.append(f"| `{r.field_code}` | {r.business_name} | {r.category} | "
                         f"{r.period_type} | {r.fdic_title} |")
        lines.append("")
    (DOCS_DIR / "data_dictionary.md").write_text("\n".join(lines), encoding="utf-8")
    return dd


def main() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(DB_PATH)) as con:
        n_fin = load_financials(con)
        n_bank = load_banks(con)
        n_ev = load_structure_events(con)
        dd = build_data_dictionary(con)
    print(f"Loaded raw_financials ({n_fin:,} rows), ref_bank ({n_bank} banks), "
          f"ref_structure_event ({n_ev} events), ref_field ({len(dd)} fields) into {DB_PATH.name}")


if __name__ == "__main__":
    main()
