-- =============================================================================
-- 02_reconciliation_checks.sql
-- Automated reconciliation & data-integrity checks on the Call Report data.
--
-- Output
--   ref_check_rule      rule catalogue (id, logic, type, tolerance)
--   recon_results       one row per rule x bank x quarter evaluated
--   exception_report    every non-PASS result, with severity, sorted for review
--
-- Rule types
--   identity  : reported total must equal the sum of its components.
--               tolerance in $ thousands (FDIC rounds each item to $1K, so
--               a sum of N rounded items can be off by a few $K).
--   ratio     : FDIC-published ratio vs our recomputation; tolerance in pct points.
--   control   : our YTD->quarter de-cumulation vs FDIC-published quarterly field.
--   threshold : regulatory minimum (PCA "well capitalized"); WARN within 1pp.
--   quality   : completeness / sign / continuity / reasonableness rules.
--
-- Severity for identity / control breaks (based on size of the break):
--   CRITICAL  |diff| >= $1B  or >= 5% of the reported line
--   HIGH      |diff| >= $100M or >= 1%
--   MEDIUM    |diff| >= $10M  or >= 0.1%
--   LOW       anything else above tolerance
-- =============================================================================

CREATE OR REPLACE TABLE ref_check_rule AS
SELECT * FROM (VALUES
 -- id      name                                              category                 logic                                                                      type        tolerance
 ('BS01', 'Balance sheet equation',                           'Balance sheet identity', 'ASSET = LIAB + EQTOT',                                                   'identity',  5.0),
 ('BS02', 'Total assets = sum of asset lines',                'Balance sheet identity', 'ASSET = CHBAL + FREPO + SC + TRADE + LNLSNET + BKPREM + ORE + INTAN + AOA','identity',  5.0),
 ('BS03', 'Total liabilities = sum of liability lines',       'Balance sheet identity', 'LIAB = DEP + FREPP + TRADEL + OTHBRF + SUBND + ALLOTHL',                 'identity',  5.0),
 ('BS04', 'Total equity = bank equity + minority interest',   'Balance sheet identity', 'EQTOT = EQ + EQCONSUB',                                                  'identity',  5.0),
 ('BS05', 'Securities = HTM + AFS + equity sec - HTM ACL',    'Balance sheet identity', 'SC = SCHA + SCAF + SCEQFV - SCHTMRES',                                   'identity',  5.0),
 ('LN01', 'Net loans = gross loans - allowance',              'Loan identity',          'LNLSNET = LNLSGR - LNATRES',                                             'identity',  5.0),
 ('LN02', 'Gross loans = sum of loan categories - unearned',  'Loan identity',          'LNLSGR = LNRE + LNCI + LNCON + LNAG + LNDEP + LNMUNI + LNFG + LS + LNSOTHER - UNINC', 'identity', 5.0),
 ('LN03', 'RE loans = domestic + foreign',                    'Loan identity',          'LNRE = LNREDOM + LNREFOR',                                               'identity',  5.0),
 ('LN04', 'Domestic RE loans = sum of property types',        'Loan identity',          'LNREDOM = LNRECONS + LNREAG + LNRERES + LNREMULT + LNRENRES',             'identity',  5.0),
 ('LN05', 'Consumer loans = sum of consumer products',        'Loan identity',          'LNCON = LNCRCD + LNAUTO + LNCONRP + LNCONOTH',                           'identity',  5.0),
 ('DP01', 'Total deposits = domestic + foreign',              'Deposit identity',       'DEP = DEPDOM + DEPFOR',                                                  'identity',  5.0),
 ('DP02', 'Domestic deposits = interest + noninterest bearing','Deposit identity',      'DEPDOM = DEPIDOM + DEPNIDOM',                                            'identity',  5.0),
 ('IS01', 'Net interest income = interest inc - interest exp','Income statement identity','NIM = INTINC - EINTEXP',                                               'identity',  5.0),
 ('IS02', 'Pre-tax income build',                             'Income statement identity','IBEFTAX = NIM + NONII - NONIX - ELNATR + IGLSEC',                      'identity',  5.0),
 ('IS03', 'Net income build',                                 'Income statement identity','NETINC = IBEFTAX - ITAX + EXTRA - NETIMIN',                            'identity',  5.0),
 ('IS04', 'Net charge-offs = charge-offs - recoveries',       'Income statement identity','NTLNLS = DRLNLS - CRLNLS',                                             'identity',  5.0),
 ('XP01', 'YTD de-cumulation ties to FDIC quarterly',         'Cross-period control',   'YTD(q) - YTD(q-1) = FDIC quarterly field (NETINCQ, NIMQ, NONIIQ, NONIXQ, ELNATQ, NTLNLSQ)', 'control', 5.0),
 ('XP02', 'No missing quarters',                              'Cross-period control',   'Every bank reports every quarter in the analysis window',                'quality',   NULL),
 ('RT01', 'CET1 ratio recomputes',                            'Ratio recompute',        'IDT1CER = RBCT1C / RWAJ',                                                'ratio',     0.01),
 ('RT02', 'Tier 1 risk-based ratio recomputes',               'Ratio recompute',        'IDT1RWAJR = RBCT1J / RWAJ',                                              'ratio',     0.01),
 ('RT03', 'Loan-to-deposit ratio recomputes',                 'Ratio recompute',        'LNLSDEPR = LNLSNET / DEP',                                               'ratio',     0.01),
 ('RT04', 'Noncurrent loan ratio recomputes',                 'Ratio recompute',        'NCLNLSR = NCLNLS / LNLSGR',                                              'ratio',     0.01),
 ('DQ01', 'Required fields populated',                        'Completeness',           'Key balance sheet, income and capital fields are not NULL',              'quality',   NULL),
 ('DQ02', 'Balances are non-negative',                        'Validity',               'Assets, loans, deposits, allowance, securities, RWA >= 0',               'quality',   NULL),
 ('RS01', 'Deposit insurance estimates reasonable',           'Reasonableness',         'DEPINS + DEPUNINS within +/-10% of DEPDOM',                              'quality',   NULL),
 ('RS02', 'Total assets QoQ move < 20%',                      'Reasonableness',         '|ASSET / prior-quarter ASSET - 1| < 20% (larger moves usually = M&A)',   'quality',   NULL),
 ('RS03', 'Goodwill <= total intangibles',                    'Reasonableness',         'INTANGW <= INTAN',                                                       'quality',   NULL),
 ('RS04', 'Allowance present when loans present',             'Reasonableness',         'LNATRES > 0 when LNLSGR > 0',                                            'quality',   NULL),
 ('RG01', 'Tier 1 leverage >= 5% (well capitalized)',         'Regulatory threshold',   'RBC1AAJ >= 5.0; WARN if < 6.0',                                          'threshold', 5.0),
 ('RG02', 'CET1 ratio >= 6.5% (well capitalized)',            'Regulatory threshold',   'IDT1CER >= 6.5; WARN if < 7.5',                                          'threshold', 6.5),
 ('RG03', 'Tier 1 RBC ratio >= 8% (well capitalized)',        'Regulatory threshold',   'IDT1RWAJR >= 8.0; WARN if < 9.0',                                        'threshold', 8.0),
 ('RG04', 'Total RBC ratio >= 10% (well capitalized)',        'Regulatory threshold',   'RBCRWAJ >= 10.0; WARN if < 11.0',                                        'threshold', 10.0)
) t(rule_id, rule_name, category, rule_logic, rule_type, tolerance);


CREATE OR REPLACE TABLE recon_results AS
WITH s AS (
    SELECT * FROM stg_call_report WHERE in_analysis_window
),

-- ---------------------------------------------------------------------------
-- Identity rules: reported value vs value rebuilt from components.
-- Missing components are treated as 0 (DQ01 separately flags missing key fields).
-- ---------------------------------------------------------------------------
identity AS (
    SELECT 'BS01' AS rule_id, cert, report_date, NULL AS detail, ASSET AS reported_value,
           LIAB + EQTOT AS expected_value FROM s
    UNION ALL SELECT 'BS02', cert, report_date, NULL, ASSET,
           CHBAL + FREPO + SC + TRADE + LNLSNET + BKPREM + coalesce(ORE,0) + INTAN + AOA FROM s
    UNION ALL SELECT 'BS03', cert, report_date, NULL, LIAB,
           DEP + coalesce(FREPP,0) + coalesce(TRADEL,0) + coalesce(OTHBRF,0) + coalesce(SUBND,0) + ALLOTHL FROM s
    UNION ALL SELECT 'BS04', cert, report_date, NULL, EQTOT, EQ + coalesce(EQCONSUB,0) FROM s
    UNION ALL SELECT 'BS05', cert, report_date, NULL, SC,
           SCHA + SCAF + coalesce(SCEQFV,0) - coalesce(SCHTMRES,0) FROM s
    UNION ALL SELECT 'LN01', cert, report_date, NULL, LNLSNET, LNLSGR - LNATRES FROM s
    UNION ALL SELECT 'LN02', cert, report_date, NULL, LNLSGR,
           LNRE + LNCI + LNCON + coalesce(LNAG,0) + coalesce(LNDEP,0) + coalesce(LNMUNI,0)
           + coalesce(LNFG,0) + coalesce(LS,0) + coalesce(LNSOTHER,0) - coalesce(UNINC,0) FROM s
    UNION ALL SELECT 'LN03', cert, report_date, NULL, LNRE, LNREDOM + coalesce(LNREFOR,0) FROM s
    UNION ALL SELECT 'LN04', cert, report_date, NULL, LNREDOM,
           coalesce(LNRECONS,0) + coalesce(LNREAG,0) + coalesce(LNRERES,0)
           + coalesce(LNREMULT,0) + coalesce(LNRENRES,0) FROM s
    UNION ALL SELECT 'LN05', cert, report_date, NULL, LNCON,
           coalesce(LNCRCD,0) + coalesce(LNAUTO,0) + coalesce(LNCONRP,0) + coalesce(LNCONOTH,0) FROM s
    UNION ALL SELECT 'DP01', cert, report_date, NULL, DEP, DEPDOM + coalesce(DEPFOR,0) FROM s
    UNION ALL SELECT 'DP02', cert, report_date, NULL, DEPDOM, DEPIDOM + DEPNIDOM FROM s
    UNION ALL SELECT 'IS01', cert, report_date, NULL, NIM, INTINC - EINTEXP FROM s
    UNION ALL SELECT 'IS02', cert, report_date, NULL, IBEFTAX,
           NIM + NONII - NONIX - ELNATR + coalesce(IGLSEC,0) FROM s
    UNION ALL SELECT 'IS03', cert, report_date, NULL, NETINC,
           IBEFTAX - ITAX + coalesce(EXTRA,0) - coalesce(NETIMIN,0) FROM s
    UNION ALL SELECT 'IS04', cert, report_date, NULL, NTLNLS, DRLNLS - CRLNLS FROM s
),

-- ---------------------------------------------------------------------------
-- Control: our de-cumulated quarter vs the FDIC-published quarterly field.
-- ---------------------------------------------------------------------------
control AS (
    SELECT 'XP01' AS rule_id, i.cert, i.report_date,
           i.field_code || ' vs ' || m.ctrl_field AS detail,
           i.quarter_value_fdic    AS reported_value,   -- FDIC quarterly
           i.quarter_value_derived AS expected_value    -- our YTD(q) - YTD(q-1)
    FROM stg_income_quarterly i
    JOIN ref_quarterly_control m ON m.field_code = i.field_code
    JOIN ref_quarter q ON q.report_date = i.report_date
    WHERE q.in_analysis_window
),

identity_eval AS (
    SELECT x.*, r.tolerance,
           x.reported_value - x.expected_value AS difference
    FROM (SELECT * FROM identity UNION ALL SELECT * FROM control) x
    JOIN ref_check_rule r USING (rule_id)
),
identity_scored AS (
    SELECT rule_id, cert, report_date, detail, reported_value, expected_value, difference,
           abs(difference) / nullif(abs(reported_value), 0) AS pct_difference,
           CASE WHEN reported_value IS NULL OR expected_value IS NULL THEN 'FAIL'
                WHEN abs(difference) <= tolerance THEN 'PASS'
                ELSE 'FAIL' END AS status,
           CASE WHEN reported_value IS NULL OR expected_value IS NULL THEN 'HIGH'
                WHEN abs(difference) <= tolerance THEN NULL
                WHEN abs(difference) >= 1000000 OR abs(difference) / nullif(abs(reported_value),0) >= 0.05  THEN 'CRITICAL'
                WHEN abs(difference) >=  100000 OR abs(difference) / nullif(abs(reported_value),0) >= 0.01  THEN 'HIGH'
                WHEN abs(difference) >=   10000 OR abs(difference) / nullif(abs(reported_value),0) >= 0.001 THEN 'MEDIUM'
                ELSE 'LOW' END AS severity
    FROM identity_eval
),

-- ---------------------------------------------------------------------------
-- Ratio recompute: FDIC ratio (pct) vs ours. Difference in percentage points.
-- ---------------------------------------------------------------------------
ratio AS (
    SELECT 'RT01' AS rule_id, cert, report_date, IDT1CER AS reported_value, 100.0 * RBCT1C / nullif(RWAJ,0) AS expected_value FROM s
    UNION ALL SELECT 'RT02', cert, report_date, IDT1RWAJR, 100.0 * RBCT1J / nullif(RWAJ,0) FROM s
    UNION ALL SELECT 'RT03', cert, report_date, LNLSDEPR,  100.0 * LNLSNET / nullif(DEP,0) FROM s
    UNION ALL SELECT 'RT04', cert, report_date, NCLNLSR,   100.0 * NCLNLS / nullif(LNLSGR,0) FROM s
),
ratio_scored AS (
    SELECT x.rule_id, cert, report_date, NULL AS detail, reported_value, expected_value,
           reported_value - expected_value AS difference,
           NULL::DOUBLE AS pct_difference,
           CASE WHEN reported_value IS NULL OR expected_value IS NULL THEN 'FAIL'
                WHEN abs(reported_value - expected_value) <= r.tolerance THEN 'PASS' ELSE 'FAIL' END AS status,
           CASE WHEN reported_value IS NULL OR expected_value IS NULL THEN 'MEDIUM'
                WHEN abs(reported_value - expected_value) <= r.tolerance THEN NULL
                WHEN abs(reported_value - expected_value) >= 0.5 THEN 'HIGH'
                WHEN abs(reported_value - expected_value) >= 0.1 THEN 'MEDIUM'
                ELSE 'LOW' END AS severity
    FROM ratio x JOIN ref_check_rule r USING (rule_id)
),

-- ---------------------------------------------------------------------------
-- Regulatory thresholds (Prompt Corrective Action "well capitalized").
-- ---------------------------------------------------------------------------
threshold AS (
    SELECT 'RG01' AS rule_id, cert, report_date, RBC1AAJ AS reported_value FROM s
    UNION ALL SELECT 'RG02', cert, report_date, IDT1CER   FROM s
    UNION ALL SELECT 'RG03', cert, report_date, IDT1RWAJR FROM s
    UNION ALL SELECT 'RG04', cert, report_date, RBCRWAJ   FROM s
),
threshold_scored AS (
    SELECT x.rule_id, cert, report_date,
           'minimum ' || r.tolerance || '%' AS detail,
           reported_value, r.tolerance AS expected_value,
           reported_value - r.tolerance AS difference, NULL::DOUBLE AS pct_difference,
           CASE WHEN reported_value IS NULL THEN 'FAIL'
                WHEN reported_value <  r.tolerance       THEN 'FAIL'
                WHEN reported_value <  r.tolerance + 1.0 THEN 'WARN'
                ELSE 'PASS' END AS status,
           CASE WHEN reported_value IS NULL THEN 'HIGH'
                WHEN reported_value <  r.tolerance       THEN 'CRITICAL'
                WHEN reported_value <  r.tolerance + 1.0 THEN 'MEDIUM' END AS severity
    FROM threshold x JOIN ref_check_rule r USING (rule_id)
),

-- ---------------------------------------------------------------------------
-- Data-quality rules
-- ---------------------------------------------------------------------------
dq_required AS (   -- DQ01: one row per bank-quarter; detail lists missing fields
    SELECT 'DQ01' AS rule_id, cert, report_date,
           concat_ws(', ',
               CASE WHEN ASSET   IS NULL THEN 'ASSET' END,
               CASE WHEN LIAB    IS NULL THEN 'LIAB' END,
               CASE WHEN EQTOT   IS NULL THEN 'EQTOT' END,
               CASE WHEN LNLSGR  IS NULL THEN 'LNLSGR' END,
               CASE WHEN LNATRES IS NULL THEN 'LNATRES' END,
               CASE WHEN DEP     IS NULL THEN 'DEP' END,
               CASE WHEN NETINC  IS NULL THEN 'NETINC' END,
               CASE WHEN NIM     IS NULL THEN 'NIM' END,
               CASE WHEN RBCT1J  IS NULL THEN 'RBCT1J' END,
               CASE WHEN RWAJ    IS NULL THEN 'RWAJ' END,
               CASE WHEN RBC1AAJ IS NULL THEN 'RBC1AAJ' END) AS missing
    FROM s
),
dq_negative AS (   -- DQ02
    SELECT 'DQ02' AS rule_id, cert, report_date,
           concat_ws(', ',
               CASE WHEN ASSET   < 0 THEN 'ASSET' END,
               CASE WHEN LNLSGR  < 0 THEN 'LNLSGR' END,
               CASE WHEN DEP     < 0 THEN 'DEP' END,
               CASE WHEN LNATRES < 0 THEN 'LNATRES' END,
               CASE WHEN SC      < 0 THEN 'SC' END,
               CASE WHEN RWAJ    < 0 THEN 'RWAJ' END) AS negatives
    FROM s
),
expected_grid AS (  -- XP02: every bank x every quarter in the window
    SELECT b.cert, q.report_date
    FROM ref_bank b CROSS JOIN ref_quarter q
    WHERE q.in_analysis_window
),
prior AS (
    SELECT s.cert, s.report_date, s.ASSET, p.ASSET AS prior_asset
    FROM s
    JOIN ref_quarter q ON q.report_date = s.report_date
    LEFT JOIN stg_call_report p ON p.cert = s.cert AND p.report_date = q.prior_quarter_date
),
quality_scored AS (
    SELECT rule_id, cert, report_date,
           CASE WHEN missing = '' THEN NULL ELSE 'missing: ' || missing END AS detail,
           NULL::DOUBLE AS reported_value, NULL::DOUBLE AS expected_value,
           NULL::DOUBLE AS difference, NULL::DOUBLE AS pct_difference,
           CASE WHEN missing = '' THEN 'PASS' ELSE 'FAIL' END AS status,
           CASE WHEN missing = '' THEN NULL ELSE 'HIGH' END AS severity
    FROM dq_required
    UNION ALL
    SELECT rule_id, cert, report_date,
           CASE WHEN negatives = '' THEN NULL ELSE 'negative: ' || negatives END,
           NULL, NULL, NULL, NULL,
           CASE WHEN negatives = '' THEN 'PASS' ELSE 'FAIL' END,
           CASE WHEN negatives = '' THEN NULL ELSE 'HIGH' END
    FROM dq_negative
    UNION ALL
    SELECT 'XP02', g.cert, g.report_date,
           CASE WHEN s.cert IS NULL THEN 'no filing found for this quarter' END,
           NULL, NULL, NULL, NULL,
           CASE WHEN s.cert IS NULL THEN 'FAIL' ELSE 'PASS' END,
           CASE WHEN s.cert IS NULL THEN 'HIGH' END
    FROM expected_grid g
    LEFT JOIN s ON s.cert = g.cert AND s.report_date = g.report_date
    UNION ALL
    SELECT 'RS01', cert, report_date,
           'insured + uninsured = ' || round(100.0 * (DEPINS + DEPUNINS) / nullif(DEPDOM,0), 1) || '% of DEPDOM',
           DEPINS + DEPUNINS, DEPDOM, DEPINS + DEPUNINS - DEPDOM,
           abs(DEPINS + DEPUNINS - DEPDOM) / nullif(DEPDOM, 0),
           CASE WHEN abs((DEPINS + DEPUNINS) / nullif(DEPDOM,0) - 1) <= 0.10 THEN 'PASS' ELSE 'WARN' END,
           CASE WHEN abs((DEPINS + DEPUNINS) / nullif(DEPDOM,0) - 1) <= 0.10 THEN NULL ELSE 'MEDIUM' END
    FROM s
    UNION ALL
    SELECT 'RS02', cert, report_date,
           'total assets ' || CASE WHEN ASSET >= prior_asset THEN '+' ELSE '' END
               || round(100.0 * (ASSET / prior_asset - 1), 1) || '% QoQ',
           ASSET, prior_asset, ASSET - prior_asset, abs(ASSET / prior_asset - 1),
           CASE WHEN prior_asset IS NULL THEN 'PASS'
                WHEN abs(ASSET / prior_asset - 1) >= 0.20 THEN 'WARN' ELSE 'PASS' END,
           CASE WHEN prior_asset IS NOT NULL AND abs(ASSET / prior_asset - 1) >= 0.20 THEN 'MEDIUM' END
    FROM prior
    UNION ALL
    SELECT 'RS03', cert, report_date, NULL, INTANGW, INTAN, INTANGW - INTAN, NULL,
           CASE WHEN coalesce(INTANGW,0) <= coalesce(INTAN,0) THEN 'PASS' ELSE 'FAIL' END,
           CASE WHEN coalesce(INTANGW,0) <= coalesce(INTAN,0) THEN NULL ELSE 'HIGH' END
    FROM s
    UNION ALL
    SELECT 'RS04', cert, report_date, NULL, LNATRES, NULL, NULL, NULL,
           CASE WHEN LNLSGR > 0 AND coalesce(LNATRES,0) <= 0 THEN 'FAIL' ELSE 'PASS' END,
           CASE WHEN LNLSGR > 0 AND coalesce(LNATRES,0) <= 0 THEN 'HIGH' END
    FROM s
),

all_results AS (
    SELECT * FROM identity_scored
    UNION ALL SELECT * FROM ratio_scored
    UNION ALL SELECT * FROM threshold_scored
    UNION ALL SELECT * FROM quality_scored
)
SELECT
    a.rule_id, r.rule_name, r.category, r.rule_type, r.rule_logic,
    a.cert, b.short_name, b.bank_name, a.report_date, q.quarter_label,
    a.detail, a.reported_value, a.expected_value, a.difference, a.pct_difference,
    a.status, a.severity
FROM all_results a
JOIN ref_check_rule r USING (rule_id)
JOIN ref_bank b USING (cert)
JOIN ref_quarter q USING (report_date);


-- ---------------------------------------------------------------------------
-- Exception report: everything that is not a clean PASS.
-- First-pass triage: cross-period exceptions (XP01 de-cumulation breaks,
-- RS02 asset jumps) that coincide with a charter merger / acquisition /
-- reorganization in the same quarter are tagged "Explained"; everything else
-- stays "Open" for an analyst to investigate.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE exception_report AS
WITH events AS (
    SELECT cert, quarter_end AS report_date,
           string_agg(event_label, '; ' ORDER BY effective_date) AS structure_events
    FROM ref_structure_event
    GROUP BY ALL
)
SELECT
    row_number() OVER (ORDER BY
        CASE r.severity WHEN 'CRITICAL' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4 END,
        r.report_date DESC, r.rule_id, r.short_name, r.detail) AS exception_id,
    r.severity, r.status, r.rule_id, r.rule_name, r.category,
    r.short_name, r.bank_name, r.cert, r.quarter_label, r.report_date,
    r.rule_logic, r.detail,
    r.reported_value, r.expected_value, r.difference, r.pct_difference,
    e.structure_events,
    CASE WHEN r.rule_id IN ('XP01', 'RS02') AND e.structure_events IS NOT NULL
         THEN 'Explained - structure change'
         ELSE 'Open - investigate' END AS resolution_status
FROM recon_results r
LEFT JOIN events e ON e.cert = r.cert AND e.report_date = r.report_date
WHERE r.status <> 'PASS'
ORDER BY exception_id;


-- Rule-level summary (one row per rule) for the README / dashboard
CREATE OR REPLACE TABLE recon_rule_summary AS
SELECT
    rule_id, rule_name, category, rule_type, rule_logic,
    count(*)                                         AS records_tested,
    count(*) FILTER (WHERE status = 'PASS')          AS passed,
    count(*) FILTER (WHERE status = 'WARN')          AS warnings,
    count(*) FILTER (WHERE status = 'FAIL')          AS failed,
    round(100.0 * count(*) FILTER (WHERE status = 'PASS') / count(*), 2) AS pass_rate_pct
FROM recon_results
GROUP BY ALL
ORDER BY rule_id;
