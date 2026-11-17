# Bank Regulatory Reporting & Variance Analytics

An end-to-end version of what a bank's **Controller / Regulatory Reporting** team does every quarter, built on public **FFIEC Call Report** data for the 20 largest U.S. banks:

1. **Ingest** the filings into a database, with a data dictionary
2. **Reconcile** them: automated checks that totals tie to their components, ratios recompute, and nothing is missing. Failures go to an **exception report** with a severity
3. **Compute** capital, profitability, asset-quality and liquidity metrics
4. **Run variance (flux) analysis**: QoQ and YoY movement on every line item, materiality flags, and a one-sentence, driver-based explanation for each material move
5. **Benchmark** JPMorgan Chase Bank, N.A. against its peers, with extracts for a Tableau dashboard

| | |
|---|---|
| **Source** | [FDIC BankFind Suite API](https://banks.data.fdic.gov/docs/): Call Report (FFIEC 031/041) financials, institution data and structure-change history |
| **Scope** | Top 20 U.S. insured banks by total assets (as of 2026Q2), **34 quarters** (2018Q1–2026Q2), with 2017 as the YoY base |
| **Stack** | Python (requests, pandas), DuckDB SQL, Tableau Public |
| **Scale** | 680 bank-quarter filings × 97 fields ≈ 66K data points; 32 check rules → 25K rule evaluations; 92K variances computed |

> Run numbers come from [`output/pipeline_summary.md`](output/pipeline_summary.md), which is regenerated on every run.

---

## Pipeline

```
FDIC BankFind API
   │  src/extract.py      top-20 universe, 38 quarters x 97 fields, institution info, merger history
   ▼
data/raw/*.json           raw snapshot (audit trail, lets the pipeline re-run offline)
   │  src/load.py         typed tables + data dictionary (docs/data_dictionary.*)
   ▼
DuckDB  data/bank_reporting.duckdb
   │  sql/01_staging.sql               wide + long staging, YTD -> quarterly de-cumulation
   │  sql/02_reconciliation_checks.sql 32 rules -> recon_results, exception_report
   │  sql/03_metrics.sql               22 metrics per bank-quarter
   │  sql/04_variance.sql              68 line items x QoQ/YoY, materiality flags
   │  src/variance_commentary.py       driver-based commentary for material moves
   │  sql/05_peer_benchmark.sql        rank / percentile vs peers, JPM scorecard
   ▼
output/tableau/*.csv  ──►  Tableau Public dashboard (Overview · Variance · Exceptions)
```

```bash
pip install -r requirements.txt
python run_pipeline.py                 # pull from the API and rebuild everything (~25s)
python run_pipeline.py --skip-extract  # rebuild from data/raw without network
python -m pytest tests                 # unit tests for the commentary generator
```

---

## 1. Ingestion & data dictionary

- The universe is chosen by rule, not by hand: the 20 largest banks by total assets in the latest quarter. Peer groups (Universal, Super-Regional, Consumer/Card, IB/Wealth, Trust & Custody) live in `src/config.py`.
- FDIC reports dollars in **thousands**. Staging keeps thousands so every number traces back to the filing; presentation tables convert to $ millions.
- **Income-statement fields in the Call Report are year-to-date.** A QoQ comparison on raw YTD numbers is wrong (Q2 YTD vs Q1 YTD always looks like +100%). `stg_income_quarterly` turns them into single quarters (`Q1 = YTD`, `Qn = YTD(n) − YTD(n−1)`). Check XP01 then tests that result against FDIC's own quarterly fields.
- [`docs/data_dictionary.md`](docs/data_dictionary.md) gives every field's business name, statement, period type (point-in-time / YTD / quarterly / ratio), unit and official FDIC title.

## 2. Reconciliation & data integrity

32 rules in [`sql/02_reconciliation_checks.sql`](sql/02_reconciliation_checks.sql), in 5 types:

| Type | Rules | Example |
|---|---|---|
| **Identity**: a total must equal the sum of its parts (±$5K rounding) | BS01–05, LN01–05, DP01–02, IS01–04 | `ASSET = LIAB + EQTOT`; `LNLSGR = Σ loan categories − unearned income`; `SC = HTM + AFS + equity securities − HTM allowance` |
| **Ratio recompute**: FDIC's ratio vs our rebuild from components | RT01–04 | `CET1 ratio = CET1 capital / RWA` |
| **Cross-period control** | XP01–02 | our YTD de-cumulation = FDIC quarterly; no missing quarters |
| **Data quality / reasonableness** | DQ01–02, RS01–04 | required fields present, no negative balances, total assets moving more than 20% QoQ |
| **Regulatory threshold** (PCA "well capitalized"; WARN within 1pp) | RG01–04 | Tier 1 leverage ≥ 5%, CET1 ≥ 6.5% |

**Severity** for a break is based on its size: CRITICAL at ≥ $1B or ≥ 5% of the line, HIGH at ≥ $100M or ≥ 1%, MEDIUM at ≥ $10M or ≥ 0.1%, LOW below that.

**Triage.** The pipeline also pulls FDIC's structure-change history (mergers, failed-bank acquisitions, reorganizations). A cross-period exception that falls in the same quarter as one of those events is tagged *Explained – structure change*. Everything else stays *Open – investigate*.

Some identities are not obvious until you test them against the data:
- Loan categories are reported **gross of unearned income**, but total loans (`LNLSGR`) is **net** of it. Summing the categories alone fails for 96 of 760 filings. The correct rule subtracts `UNINC`.
- Total securities ≠ HTM + AFS. Since ASU 2016-01 it also includes **equity securities at fair value**, and since CECL it is **net of the HTM allowance**. With both terms, the rule ties on every filing.

## 3. Key metrics

[`sql/03_metrics.sql`](sql/03_metrics.sql) has 22 metrics in 4 groups. Definitions and direction ("higher is better") are in the `ref_metric` table.

- **Capital**: Tier 1 leverage, CET1, Tier 1 / total risk-based ratios, RWA density
- **Profitability**: NIM, ROA, ROE, efficiency ratio, fee-income share
- **Asset quality**: net charge-off rate, noncurrent and 30–89 DPD ratios, allowance/loans, reserve coverage, provision/NCO
- **Liquidity**: loan-to-deposit, uninsured deposit share, noninterest-bearing deposit share, liquid assets/assets

Flow ratios use the **single quarter, annualized**, over a 2-point average balance. P&L uses FDIC's published quarterly fields (`NETINCQ`, `NIMQ`, …), which stay correct when a bank merges in another charter mid-year.

## 4. Variance (flux) analysis

- 68 line items (balance sheet, loan and deposit mix, capital, quarterly P&L), compared **QoQ** and **YoY**.
- **Materiality: |Δ%| ≥ 10% *and* |Δ$| ≥ $1B.** The AND removes two kinds of noise: large % moves on small balances, and $ moves that are tiny next to a multi-trillion balance sheet. If the prior value is ≤ 0 (for example a prior-quarter loss), % change is "n.m." and the $ test decides alone. Both thresholds are set in `src/config.py`.
- **Driver commentary.** Line items are arranged in a roll-up (`ref_line_item.parent_code`) that mirrors the identities verified in step 2, so a parent's change equals the signed sum of its children's changes. For each material move, `src/variance_commentary.py` names the largest children that drove it and the largest offset:

  > *Consumer loans +51.8% QoQ (+$114.5B), driven by credit card loans +$102.4B. Note: bank merged Discover Bank on 2025-05-18 – change includes acquired balances, not organic.*

  > *(JPM, 2023Q2) Net income +76.9% YoY (+$6.1B), driven by net interest income +$7.7B and noninterest income +$3.8B, partly offset by higher noninterest expense (+$2.3B). Note: bank acquired failed bank First Republic Bank on 2023-05-01 – change includes acquired balances, not organic.*

  Lines with no further breakdown in the Call Report say how much of their parent's move they explain, and ask for commentary from the business. The generator only explains what the data shows.

## 5. Peer benchmarking & dashboard

`fct_peer_benchmark` gives every bank, quarter and metric a peer median, P25/P75, peer-group median, rank and a direction-aware percentile (100 = best). `fct_focus_scorecard` is JPM's latest-quarter scorecard.

Tableau Public dashboard: **[JPM Peer Benchmark](https://public.tableau.com/app/profile/savannah.bai/viz/JPMPeerBenchmark/Overview)**. Build steps are in [`docs/tableau_guide.md`](docs/tableau_guide.md).

---

## Key findings

<!--
  Write this section yourself, in your own words. output/pipeline_summary.md has the facts.
  Suggested angles:
   - Data integrity: what tied and what didn't, and why (unearned income, ASU 2016-01 / CECL securities, YTD breaks at charter mergers)
   - The open exceptions: 2020Q1 asset jumps at custody/IB banks (BK, STT, SCHW, MS, GS) – what happened in March 2020?
   - RS01: why can insured + uninsured deposit estimates differ from balance-sheet deposits (HBAN up to 40%)?
   - JPM vs peers: top-quartile ROE/ROA and CET1, but bottom-quartile leverage ratio and NCO rate – how do these fit together?
   - A variance you find interesting (e.g. JPM 2026Q2 net income driven by securities gains; BMO US 2026Q2 loss)
-->

_TODO_

---

## Limitations

- **Bank level, not holding company.** The Call Report covers the insured bank (e.g. JPMorgan Chase Bank, N.A.), not JPMorgan Chase & Co. Holding-company figures (FR Y-9C) differ, so these numbers won't match the 10-Q.
- Average-balance ratios use 2 points (this and prior quarter end); FDIC's YTD ratios use more. The difference is small; both are stored.
- In merger quarters, YTD-derived lines without an FDIC quarterly equivalent (e.g. interest income, taxes) are not comparable. Those rows carry the merger in `structure_events`.
- Fields first reported in 2018 (e.g. equity securities under ASU 2016-01) have no 2017 base, so 2018 YoY roll-ups for those parents are incomplete.

## Repository layout

```
run_pipeline.py            orchestrates all steps
src/                       config, extract, load, run_sql, variance_commentary, export
sql/                       01_staging → 05_peer_benchmark (numbered, run in order)
docs/                      data dictionary (.md/.csv), Tableau build guide
data/raw/                  raw API snapshot (JSON) + FDIC field definitions
output/tableau/            Tableau extracts (CSV)
output/pipeline_summary.md numbers from the latest run
tests/                     unit tests
```
