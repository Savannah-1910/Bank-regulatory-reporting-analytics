-- =============================================================================
-- 03_metrics.sql
-- Key regulatory & financial metrics per bank per quarter.
--
--   ref_metric          metric catalogue: definition, unit, direction ("higher is better")
--   fct_bank_metrics    wide: one row per bank x quarter (analysis window only)
--   fct_metrics_long    long: one row per bank x quarter x metric (feeds peer benchmarking)
--
-- Conventions
--   * Dollar amounts converted from $ thousands to $ millions (_mm).
--   * Flow-based ratios use the single quarter, annualized (x4), over the
--     average of this and the prior quarter-end balance (2-point average).
--     FDIC's own YTD ratios (NIMY, ROA, ...) use more averaging points, so ours
--     differ slightly; we keep ours because they move with the quarter being
--     analysed instead of being smoothed across the year.
--   * Merger quarters distort average-balance ratios (the average mixes the
--     pre- and post-merger balance sheet). See ref_structure_event.
-- =============================================================================

CREATE OR REPLACE TABLE ref_metric AS
SELECT * FROM (VALUES
 -- code                       name                                   category         unit   higher_is_better  definition
 ('total_assets_mm',          'Total assets',                         'Size',           '$M',  0,  'ASSET'),
 ('tier1_leverage_pct',       'Tier 1 leverage ratio',                'Capital',        '%',   1,  'Tier 1 capital / average total assets for leverage purposes (FDIC RBC1AAJ)'),
 ('cet1_ratio_pct',           'CET1 ratio',                           'Capital',        '%',   1,  'Common equity tier 1 capital / risk-weighted assets (RBCT1C / RWAJ)'),
 ('tier1_rbc_ratio_pct',      'Tier 1 risk-based capital ratio',      'Capital',        '%',   1,  'Tier 1 capital / risk-weighted assets (RBCT1J / RWAJ)'),
 ('total_rbc_ratio_pct',      'Total risk-based capital ratio',       'Capital',        '%',   1,  'Total capital / risk-weighted assets (FDIC RBCRWAJ)'),
 ('rwa_density_pct',          'RWA density',                          'Capital',        '%',   0,  'Risk-weighted assets / total assets'),
 ('nim_pct',                  'Net interest margin',                  'Profitability',  '%',   1,  'Quarterly net interest income x4 / avg earning assets'),
 ('roa_pct',                  'Return on assets (ROA)',               'Profitability',  '%',   1,  'Quarterly net income x4 / avg total assets'),
 ('roe_pct',                  'Return on equity (ROE)',               'Profitability',  '%',   1,  'Quarterly net income x4 / avg bank equity capital'),
 ('efficiency_ratio_pct',     'Efficiency ratio',                     'Profitability',  '%',  -1,  'Noninterest expense / (net interest income + noninterest income)'),
 ('fee_income_share_pct',     'Noninterest income share of revenue',  'Profitability',  '%',   0,  'Noninterest income / (net interest income + noninterest income)'),
 ('nco_rate_pct',             'Net charge-off rate',                  'Asset Quality',  '%',  -1,  'Quarterly net charge-offs x4 / avg gross loans'),
 ('noncurrent_loans_pct',     'Noncurrent loan ratio',                'Asset Quality',  '%',  -1,  'Loans 90+ days past due or nonaccrual / gross loans'),
 ('past_due_30_89_pct',       '30-89 days past due ratio',            'Asset Quality',  '%',  -1,  'Loans 30-89 days past due / gross loans'),
 ('acl_to_loans_pct',         'Allowance to loans',                   'Asset Quality',  '%',   0,  'Allowance for credit losses / gross loans'),
 ('acl_coverage_pct',         'Reserve coverage of noncurrent loans', 'Asset Quality',  '%',   1,  'Allowance for credit losses / noncurrent loans'),
 ('provision_to_nco_pct',     'Provision / net charge-offs',          'Asset Quality',  '%',   0,  'Quarterly provision / quarterly net charge-offs (>100% = reserve build)'),
 ('loan_to_deposit_pct',      'Loan-to-deposit ratio',                'Liquidity',      '%',   0,  'Net loans / total deposits'),
 ('uninsured_deposit_pct',    'Uninsured deposit share',              'Liquidity',      '%',  -1,  'Estimated uninsured / (estimated insured + uninsured) deposits'),
 ('nib_deposit_pct',          'Noninterest-bearing deposit share',    'Liquidity',      '%',   1,  'Noninterest-bearing / total domestic deposits'),
 ('liquid_assets_pct',        'Liquid assets to total assets',        'Liquidity',      '%',   1,  '(Cash + fed funds sold & reverse repos + securities) / total assets'),
 ('securities_to_assets_pct', 'Securities to total assets',           'Liquidity',      '%',   0,  'Securities / total assets')
) t(metric_code, metric_name, category, unit, higher_is_better, definition);


CREATE OR REPLACE TABLE fct_bank_metrics AS
WITH base AS (
    SELECT s.*, q.prior_quarter_date,
           p.ASSET   AS p_asset,
           p.EQ      AS p_eq,
           p.LNLSGR  AS p_lnlsgr,
           p.ERNAST  AS p_ernast
    FROM stg_call_report s
    JOIN ref_quarter q USING (report_date)
    LEFT JOIN stg_call_report p
           ON p.cert = s.cert AND p.report_date = q.prior_quarter_date
    WHERE s.in_analysis_window
)
SELECT
    cert,
    report_date,
    quarter_label,

    -- ---- Size & balances ($M)
    ASSET   / 1e3 AS total_assets_mm,
    LNLSGR  / 1e3 AS gross_loans_mm,
    DEP     / 1e3 AS deposits_mm,
    EQTOT   / 1e3 AS total_equity_mm,
    RWAJ    / 1e3 AS rwa_mm,
    RBCT1J  / 1e3 AS tier1_capital_mm,

    -- ---- Quarterly P&L ($M) - FDIC single-quarter fields (merger-safe)
    NIMQ    / 1e3 AS net_interest_income_q_mm,
    NONIIQ  / 1e3 AS noninterest_income_q_mm,
    NONIXQ  / 1e3 AS noninterest_expense_q_mm,
    ELNATQ  / 1e3 AS provision_q_mm,
    NETINCQ / 1e3 AS net_income_q_mm,
    NTLNLSQ / 1e3 AS net_charge_offs_q_mm,

    -- ---- Capital
    RBC1AAJ                                             AS tier1_leverage_pct,
    100.0 * RBCT1C / nullif(RWAJ, 0)                    AS cet1_ratio_pct,
    100.0 * RBCT1J / nullif(RWAJ, 0)                    AS tier1_rbc_ratio_pct,
    RBCRWAJ                                             AS total_rbc_ratio_pct,
    100.0 * RWAJ / nullif(ASSET, 0)                     AS rwa_density_pct,

    -- ---- Profitability (quarter annualized, 2-point averages)
    100.0 * NIMQ * 4    / nullif((ERNAST + p_ernast) / 2, 0)  AS nim_pct,
    100.0 * NETINCQ * 4 / nullif((ASSET + p_asset) / 2, 0)    AS roa_pct,
    100.0 * NETINCQ * 4 / nullif((EQ + p_eq) / 2, 0)          AS roe_pct,
    100.0 * NONIXQ / nullif(NIMQ + NONIIQ, 0)                 AS efficiency_ratio_pct,
    100.0 * NONIIQ / nullif(NIMQ + NONIIQ, 0)                 AS fee_income_share_pct,

    -- ---- Asset quality
    100.0 * NTLNLSQ * 4 / nullif((LNLSGR + p_lnlsgr) / 2, 0)  AS nco_rate_pct,
    100.0 * NCLNLS  / nullif(LNLSGR, 0)                       AS noncurrent_loans_pct,
    100.0 * P3ASSET / nullif(LNLSGR, 0)                       AS past_due_30_89_pct,
    100.0 * LNATRES / nullif(LNLSGR, 0)                       AS acl_to_loans_pct,
    100.0 * LNATRES / nullif(NCLNLS, 0)                       AS acl_coverage_pct,
    100.0 * ELNATQ  / nullif(NTLNLSQ, 0)                      AS provision_to_nco_pct,

    -- ---- Liquidity & funding
    100.0 * LNLSNET  / nullif(DEP, 0)                         AS loan_to_deposit_pct,
    100.0 * DEPUNINS / nullif(DEPINS + DEPUNINS, 0)           AS uninsured_deposit_pct,
    100.0 * DEPNIDOM / nullif(DEPDOM, 0)                      AS nib_deposit_pct,
    100.0 * (CHBAL + FREPO + SC) / nullif(ASSET, 0)           AS liquid_assets_pct,
    100.0 * SC / nullif(ASSET, 0)                             AS securities_to_assets_pct,

    -- ---- FDIC-published YTD ratios kept for reference / cross-check
    NIMY  AS fdic_nim_ytd_pct,
    ROA   AS fdic_roa_ytd_pct,
    ROE   AS fdic_roe_ytd_pct,
    EEFFR AS fdic_efficiency_ytd_pct,

    -- Flag quarters where a merger / reorganization makes ratios less comparable
    EXISTS (SELECT 1 FROM ref_structure_event e
            WHERE e.cert = base.cert AND e.quarter_end = base.report_date
              AND e.change_code IN (810, 811))                AS merger_quarter
FROM base;


CREATE OR REPLACE TABLE fct_metrics_long AS
SELECT u.cert, u.report_date, u.quarter_label, u.merger_quarter,
       u.metric_code, m.metric_name, m.category, m.unit, m.higher_is_better,
       u.value
FROM (
    UNPIVOT fct_bank_metrics
    ON total_assets_mm, tier1_leverage_pct, cet1_ratio_pct, tier1_rbc_ratio_pct,
       total_rbc_ratio_pct, rwa_density_pct, nim_pct, roa_pct, roe_pct,
       efficiency_ratio_pct, fee_income_share_pct, nco_rate_pct, noncurrent_loans_pct,
       past_due_30_89_pct, acl_to_loans_pct, acl_coverage_pct, provision_to_nco_pct,
       loan_to_deposit_pct, uninsured_deposit_pct, nib_deposit_pct, liquid_assets_pct,
       securities_to_assets_pct
    INTO NAME metric_code VALUE value
) u
JOIN ref_metric m USING (metric_code);
