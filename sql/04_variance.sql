-- =============================================================================
-- 04_variance.sql
-- QoQ and YoY variance (flux) analysis by line item, with materiality flags.
--
--   ref_line_item        line items in scope, display order, parent/child roll-up
--   fct_line_item_value  bank x quarter x line item ($ thousands)
--   fct_variance         bank x quarter x line item x comparison (QoQ / YoY)
--
-- Materiality: flagged when |% change| >= {variance_pct_threshold} AND |$ change| >= ${variance_amount_threshold_k}K.
-- If the prior value is <= 0 (e.g. a prior-quarter loss) the % change is not
-- meaningful ("n.m.") and the $ test alone decides.
--
-- The roll-up (parent_code / sign) mirrors the identities verified in
-- 02_reconciliation_checks.sql, so a parent's change always equals the signed sum
-- of its children's changes. The Python step (src/variance_commentary.py)
-- uses it to name the children that drove each flagged move.
--
-- Income statement lines use single-quarter values from stg_income_quarterly
-- (suffix _Q); balance sheet lines are quarter-end balances.
-- =============================================================================

CREATE OR REPLACE TABLE ref_line_item AS
SELECT * FROM (VALUES
 -- line_code     display name                              section              parent       sign  sort
 ('ASSET',       'Total assets',                           'Balance sheet',      NULL,         1,  100),
 ('CHBAL',       'Cash & due from banks',                  'Balance sheet',      'ASSET',      1,  110),
 ('FREPO',       'Fed funds sold & reverse repos',         'Balance sheet',      'ASSET',      1,  120),
 ('SC',          'Securities',                             'Balance sheet',      'ASSET',      1,  130),
 ('SCHA',        'HTM securities',                         'Balance sheet',      'SC',         1,  131),
 ('SCAF',        'AFS securities',                         'Balance sheet',      'SC',         1,  132),
 ('SCEQFV',      'Equity securities',                      'Balance sheet',      'SC',         1,  133),
 ('SCHTMRES',    'HTM securities allowance',               'Balance sheet',      'SC',        -1,  134),
 ('TRADE',       'Trading assets',                         'Balance sheet',      'ASSET',      1,  140),
 ('LNLSNET',     'Net loans',                              'Balance sheet',      'ASSET',      1,  150),
 ('LNLSGR',      'Gross loans',                            'Loans',              'LNLSNET',    1,  200),
 ('LNRE',        'Real estate loans',                      'Loans',              'LNLSGR',     1,  210),
 ('LNRERES',     '1-4 family mortgages',                   'Loans',              'LNRE',       1,  211),
 ('LNREMULT',    'Multifamily loans',                      'Loans',              'LNRE',       1,  212),
 ('LNRENRES',    'Non-farm non-residential CRE',           'Loans',              'LNRE',       1,  213),
 ('LNRECONS',    'Construction loans',                     'Loans',              'LNRE',       1,  214),
 ('LNREAG',      'Farmland loans',                         'Loans',              'LNRE',       1,  215),
 ('LNREFOR',     'Foreign-office RE loans',                'Loans',              'LNRE',       1,  216),
 ('LNCI',        'C&I loans',                              'Loans',              'LNLSGR',     1,  220),
 ('LNCON',       'Consumer loans',                         'Loans',              'LNLSGR',     1,  230),
 ('LNCRCD',      'Credit card loans',                      'Loans',              'LNCON',      1,  231),
 ('LNAUTO',      'Auto loans',                             'Loans',              'LNCON',      1,  232),
 ('LNCONRP',     'Other revolving consumer loans',         'Loans',              'LNCON',      1,  233),
 ('LNCONOTH',    'Other consumer loans',                   'Loans',              'LNCON',      1,  234),
 ('LNAG',        'Agricultural loans',                     'Loans',              'LNLSGR',     1,  240),
 ('LNDEP',       'Loans to depository institutions',       'Loans',              'LNLSGR',     1,  241),
 ('LNMUNI',      'Municipal loans',                        'Loans',              'LNLSGR',     1,  242),
 ('LNFG',        'Foreign government loans',               'Loans',              'LNLSGR',     1,  243),
 ('LS',          'Leases',                                 'Loans',              'LNLSGR',     1,  244),
 ('LNSOTHER',    'All other loans',                        'Loans',              'LNLSGR',     1,  245),
 ('UNINC',       'Unearned income',                        'Loans',              'LNLSGR',    -1,  246),
 ('LNATRES',     'Allowance for credit losses',            'Loans',              'LNLSNET',   -1,  250),
 ('BKPREM',      'Premises & fixed assets',                'Balance sheet',      'ASSET',      1,  160),
 ('ORE',         'Other real estate owned',                'Balance sheet',      'ASSET',      1,  161),
 ('INTAN',       'Intangible assets',                      'Balance sheet',      'ASSET',      1,  170),
 ('AOA',         'All other assets',                       'Balance sheet',      'ASSET',      1,  180),
 ('LIAB',        'Total liabilities',                      'Balance sheet',      NULL,         1,  300),
 ('DEP',         'Total deposits',                         'Deposits',           'LIAB',       1,  310),
 ('DEPNIDOM',    'Noninterest-bearing domestic deposits',  'Deposits',           'DEP',        1,  311),
 ('DEPIDOM',     'Interest-bearing domestic deposits',     'Deposits',           'DEP',        1,  312),
 ('DEPFOR',      'Foreign-office deposits',                'Deposits',           'DEP',        1,  313),
 ('DEPUNINS',    'Estimated uninsured deposits',           'Deposits',           NULL,         1,  314),
 ('FREPP',       'Fed funds purchased & repos',            'Balance sheet',      'LIAB',       1,  320),
 ('TRADEL',      'Trading liabilities',                    'Balance sheet',      'LIAB',       1,  330),
 ('OTHBRF',      'Other borrowed funds',                   'Balance sheet',      'LIAB',       1,  340),
 ('SUBND',       'Subordinated debt',                      'Balance sheet',      'LIAB',       1,  350),
 ('ALLOTHL',     'All other liabilities',                  'Balance sheet',      'LIAB',       1,  360),
 ('EQTOT',       'Total equity capital',                   'Balance sheet',      NULL,         1,  400),
 ('EQ',          'Bank equity capital',                    'Balance sheet',      'EQTOT',      1,  410),
 ('EQCONSUB',    'Minority interest',                      'Balance sheet',      'EQTOT',      1,  420),
 ('RWAJ',        'Risk-weighted assets',                   'Regulatory capital', NULL,         1,  500),
 ('RBCT1J',      'Tier 1 capital',                         'Regulatory capital', NULL,         1,  510),
 ('NCLNLS',      'Noncurrent loans',                       'Asset quality',      NULL,         1,  520),
 ('P3ASSET',     'Loans 30-89 days past due',              'Asset quality',      NULL,         1,  530),
 ('NETINC_Q',    'Net income',                             'Income statement',   NULL,         1,  600),
 ('NIM_Q',       'Net interest income',                    'Income statement',   'NETINC_Q',   1,  610),
 ('INTINC_Q',    'Interest income',                        'Income statement',   'NIM_Q',      1,  611),
 ('EINTEXP_Q',   'Interest expense',                       'Income statement',   'NIM_Q',     -1,  612),
 ('NONII_Q',     'Noninterest income',                     'Income statement',   'NETINC_Q',   1,  620),
 ('NONIX_Q',     'Noninterest expense',                    'Income statement',   'NETINC_Q',  -1,  630),
 ('ELNATR_Q',    'Provision for credit losses',            'Income statement',   'NETINC_Q',  -1,  640),
 ('IGLSEC_Q',    'Securities gains/losses',                'Income statement',   'NETINC_Q',   1,  650),
 ('ITAX_Q',      'Income taxes',                           'Income statement',   'NETINC_Q',  -1,  660),
 ('EXTRA_Q',     'Discontinued operations',                'Income statement',   'NETINC_Q',   1,  670),
 ('NETIMIN_Q',   'Minority interest in net income',        'Income statement',   'NETINC_Q',  -1,  680),
 ('NTLNLS_Q',    'Net charge-offs',                        'Income statement',   NULL,         1,  700),
 ('DRLNLS_Q',    'Gross charge-offs',                      'Income statement',   'NTLNLS_Q',   1,  710),
 ('CRLNLS_Q',    'Recoveries',                             'Income statement',   'NTLNLS_Q',  -1,  720)
) t(line_code, line_name, section, parent_code, sign, sort_order);


CREATE OR REPLACE TABLE fct_line_item_value AS
SELECT l.cert, l.report_date, l.field_code AS line_code, l.value
FROM stg_call_report_long l
JOIN ref_line_item li ON li.line_code = l.field_code
UNION ALL
SELECT i.cert, i.report_date, i.field_code || '_Q', i.quarter_value
FROM stg_income_quarterly i
JOIN ref_line_item li ON li.line_code = i.field_code || '_Q';


CREATE OR REPLACE TABLE fct_variance AS
WITH cmp AS (
    SELECT v.cert, v.report_date, v.line_code, v.value,
           c.comparison, c.prior_date, p.value AS prior_value
    FROM fct_line_item_value v
    JOIN ref_quarter q ON q.report_date = v.report_date
    CROSS JOIN LATERAL (VALUES ('QoQ', q.prior_quarter_date), ('YoY', q.prior_year_date)) c(comparison, prior_date)
    LEFT JOIN fct_line_item_value p
           ON p.cert = v.cert AND p.line_code = v.line_code AND p.report_date = c.prior_date
    WHERE q.in_analysis_window
),
calc AS (
    SELECT *,
           value - prior_value AS change,
           CASE WHEN prior_value > 0 THEN (value - prior_value) / prior_value END AS pct_change
    FROM cmp
)
SELECT
    c.cert, b.short_name, b.peer_group, c.report_date, q.quarter_label,
    c.comparison, c.prior_date,
    li.section, li.line_code, li.line_name, li.parent_code, li.sign, li.sort_order,
    c.value, c.prior_value, c.change, c.pct_change,
    (c.prior_value IS NOT NULL
     AND abs(c.change) >= {variance_amount_threshold_k}
     AND (c.pct_change IS NULL OR abs(c.pct_change) >= {variance_pct_threshold})) AS is_material,
    -- merger / acquisition in the comparison window (QoQ: this quarter; YoY: last 4 quarters)
    (SELECT string_agg(e.event_label, '; ' ORDER BY e.effective_date)
       FROM ref_structure_event e
      WHERE e.cert = c.cert AND e.change_code IN (810, 811)
        AND e.quarter_end >  c.prior_date
        AND e.quarter_end <= c.report_date) AS structure_events
FROM calc c
JOIN ref_line_item li USING (line_code)
JOIN ref_bank b USING (cert)
JOIN ref_quarter q ON q.report_date = c.report_date;
