"""
Step 5 - Export Tableau-ready CSVs and a run summary.

output/tableau/
  banks.csv                  bank dimension (short name, peer group, HQ)
  bank_quarter_metrics.csv   one row per bank x quarter, all metrics   -> Overview page
  peer_benchmark.csv         bank x quarter x metric, percentile/rank  -> Overview / peer charts
  focus_scorecard.csv        JPM vs peers, latest quarter               -> Overview KPI tiles
  variance_analysis.csv      bank x quarter x line x QoQ/YoY, commentary -> Variance page
  exception_report.csv       failed / warning checks with triage status -> Exceptions page
  recon_rule_summary.csv     pass/fail counts per rule                  -> Exceptions page

output/pipeline_summary.md   numbers produced by this run (for README / resume)
"""
import json

import duckdb

from config import (DB_PATH, OUTPUT_DIR, RAW_DIR, TABLEAU_DIR,
                    VARIANCE_AMOUNT_THRESHOLD_K, VARIANCE_PCT_THRESHOLD)

EXPORTS = {
    "banks": "SELECT * FROM ref_bank ORDER BY asset_rank",
    "bank_quarter_metrics": """
        SELECT b.short_name, b.bank_name, b.peer_group, b.is_focus_bank, b.asset_rank, m.*
        FROM fct_bank_metrics m JOIN ref_bank b USING (cert)
        ORDER BY report_date, asset_rank""",
    "peer_benchmark": "SELECT * FROM fct_peer_benchmark ORDER BY report_date, metric_code, peer_rank",
    "focus_scorecard": "SELECT * FROM fct_focus_scorecard",
    "variance_analysis": """
        SELECT cert, short_name, peer_group, report_date, quarter_label, comparison, prior_date,
               section, line_code, line_name, parent_code, sort_order,
               value / 1e3       AS value_mm,
               prior_value / 1e3 AS prior_value_mm,
               change / 1e3      AS change_mm,
               pct_change, is_material, is_inorganic, structure_events,
               commentary, top_driver_name, top_driver_share
        FROM fct_variance_report
        ORDER BY report_date, short_name, comparison, sort_order""",
    "exception_report": "SELECT * FROM exception_report ORDER BY exception_id",
    "recon_rule_summary": "SELECT * FROM recon_rule_summary ORDER BY rule_id",
}


def export_csvs(con) -> dict:
    TABLEAU_DIR.mkdir(parents=True, exist_ok=True)
    counts = {}
    for name, sql in EXPORTS.items():
        df = con.sql(sql).df()
        df.to_csv(TABLEAU_DIR / f"{name}.csv", index=False)
        counts[name] = len(df)
    return counts


def md_table(df) -> str:
    cols = list(df.columns)
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    for row in df.itertuples(index=False):
        cells = []
        for v in row:
            if isinstance(v, float):
                cells.append(f"{v:,.2f}")
            else:
                cells.append("" if v is None else str(v))
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def write_summary(con, counts: dict) -> None:
    manifest = json.loads((RAW_DIR / "manifest.json").read_text())
    one = lambda sql: con.sql(sql).fetchall()[0][0]

    n_banks = one("SELECT count(*) FROM ref_bank")
    n_q = one("SELECT count(*) FROM ref_quarter WHERE in_analysis_window")
    q_first = one("SELECT min(quarter_label) FROM ref_quarter WHERE in_analysis_window")
    q_last = one("SELECT max(quarter_label) FROM ref_quarter WHERE in_analysis_window")
    n_records = one("SELECT count(*) FROM stg_call_report WHERE in_analysis_window")
    n_points = one("""SELECT count(*) FROM stg_call_report_long l
                      JOIN ref_quarter q USING (report_date) WHERE q.in_analysis_window""")
    n_fields = one("SELECT count(*) FROM ref_field")
    n_rules = one("SELECT count(*) FROM ref_check_rule")
    n_evals = one("SELECT count(*) FROM recon_results")
    n_exc = one("SELECT count(*) FROM exception_report")
    n_open = one("SELECT count(*) FROM exception_report WHERE resolution_status LIKE 'Open%'")
    n_lines = one("SELECT count(*) FROM ref_line_item")
    n_var = one("SELECT count(*) FROM fct_variance")
    n_mat = one("SELECT count(*) FROM fct_variance WHERE is_material")
    n_driver = one("SELECT count(*) FROM fct_variance_commentary WHERE top_driver_code IS NOT NULL")
    n_inorg = one("SELECT count(*) FROM fct_variance_commentary WHERE is_inorganic")

    by_sev = con.sql("""
        SELECT severity, status, resolution_status, count(*) AS exceptions
        FROM exception_report
        GROUP BY severity, status, resolution_status
        ORDER BY CASE severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
                 status, resolution_status""").df()
    rules = con.sql("""SELECT rule_id, rule_name, records_tested, passed, warnings, failed
                       FROM recon_rule_summary ORDER BY rule_id""").df()
    open_exc = con.sql("""
        SELECT rule_id, short_name, quarter_label, severity, detail
        FROM exception_report WHERE resolution_status LIKE 'Open%' AND rule_id <> 'RS01'
        ORDER BY report_date""").df()
    rs01 = con.sql("""
        SELECT short_name, count(*) AS quarters_flagged, min(quarter_label) AS first_q, max(quarter_label) AS last_q
        FROM exception_report WHERE rule_id = 'RS01' GROUP BY 1 ORDER BY 2 DESC""").df()
    score = con.sql("""
        SELECT category, metric_name,
               round(value, 2) AS jpm, round(peer_median, 2) AS peer_median,
               peer_rank || ' / ' || peer_count AS rank, peer_percentile AS percentile, standing
        FROM fct_focus_scorecard""").df()
    focus_var = con.sql("""
        SELECT quarter_label, commentary FROM fct_variance_report
        WHERE cert = 628 AND comparison = 'QoQ' AND is_material AND parent_code IS NULL
          AND report_date = (SELECT max(report_date) FROM fct_variance_report)
        ORDER BY sort_order""").df()

    out = [
        "# Pipeline run summary",
        "",
        f"_Auto-generated by `src/export.py`. Data extracted {manifest['extracted_at_utc']} "
        f"from {manifest['api_base']}. Latest quarter: {q_last}._",
        "",
        "## Scale",
        "",
        f"- Banks: **{n_banks}** (largest U.S. insured banks by total assets at {q_last})",
        f"- Quarters analysed: **{n_q}** ({q_first} - {q_last}); 2017 also pulled as the YoY base",
        f"- Bank-quarter filings in window: **{n_records:,}**; Call Report fields per filing: **{n_fields}**",
        f"- Data points (bank x quarter x field) in window: **{n_points:,}**",
        "",
        "## Reconciliation & data integrity",
        "",
        f"- **{n_rules}** automated rules, **{n_evals:,}** rule evaluations",
        f"- **{n_exc}** exceptions (FAIL or WARN); **{n_exc - n_open}** auto-explained by a merger / "
        f"acquisition in the same quarter, **{n_open}** open for review",
        "",
        md_table(by_sev),
        "",
        "### Results by rule",
        "",
        md_table(rules),
        "",
        "### Open exceptions (excluding RS01)",
        "",
        md_table(open_exc),
        "",
        "### RS01 - insured + uninsured deposit estimates vs. domestic deposits (>10% gap)",
        "",
        md_table(rs01),
        "",
        "## Variance analysis",
        "",
        f"- {n_lines} line items x {n_banks} banks x {n_q} quarters x (QoQ, YoY) = **{n_var:,}** variances computed",
        f"- Materiality: |change| >= {VARIANCE_PCT_THRESHOLD:.0%} **and** >= "
        f"${VARIANCE_AMOUNT_THRESHOLD_K / 1e6:,.0f}B -> **{n_mat:,}** material variances",
        f"- Driver-based commentary (named components) for **{n_driver:,}**; "
        f"**{n_inorg:,}** material variances coincide with a merger/acquisition",
        "",
        "### JPM - material top-level QoQ moves, latest quarter",
        "",
        md_table(focus_var),
        "",
        f"## JPM vs. peers - {q_last}",
        "",
        md_table(score),
        "",
        "## Tableau extracts",
        "",
        md_table(__import__("pandas").DataFrame(
            [{"file": f"output/tableau/{k}.csv", "rows": v} for k, v in counts.items()])),
        "",
    ]
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / "pipeline_summary.md").write_text("\n".join(out), encoding="utf-8")


def main() -> None:
    with duckdb.connect(str(DB_PATH)) as con:
        counts = export_csvs(con)
        write_summary(con, counts)
    for k, v in counts.items():
        print(f"  {k + '.csv':<28} {v:>8,} rows")
    print(f"  summary -> {OUTPUT_DIR / 'pipeline_summary.md'}")


if __name__ == "__main__":
    main()
