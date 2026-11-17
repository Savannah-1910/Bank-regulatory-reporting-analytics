-- =============================================================================
-- 01_staging.sql
-- Clean, typed staging layer on top of raw_financials.
--   stg_call_report        wide: one row per bank x quarter (FDIC field codes kept as-is
--                          so every number can be traced back to the Call Report)
--   stg_call_report_long   long: one row per bank x quarter x field (the "record" grain)
--   stg_income_quarterly   YTD income-statement fields de-cumulated to single quarters
--   ref_quarter            calendar of report dates with prior-quarter / prior-year keys
-- Units: USD thousands (as published by FDIC).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Quarter calendar. Prior-period keys are derived with date math rather than
-- LAG() so that a missing quarter shows up as a NULL comparison instead of
-- silently comparing against the wrong period.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE ref_quarter AS
SELECT DISTINCT
    REPDTE                                                     AS report_date,
    year(REPDTE)                                               AS report_year,
    quarter(REPDTE)                                            AS report_quarter,
    year(REPDTE) || 'Q' || quarter(REPDTE)                     AS quarter_label,
    last_day(REPDTE - INTERVAL 3 MONTH)                        AS prior_quarter_date,
    last_day(REPDTE - INTERVAL 12 MONTH)                       AS prior_year_date,
    REPDTE >= DATE '{analysis_start}'                          AS in_analysis_window
FROM raw_financials
ORDER BY report_date;

CREATE OR REPLACE TABLE stg_call_report AS
SELECT
    r.CERT                       AS cert,
    r.REPDTE                     AS report_date,
    q.quarter_label,
    q.in_analysis_window,
    r.NAMEFULL                   AS bank_name_as_reported,
    r.* EXCLUDE (CERT, REPDTE, NAMEFULL)
FROM raw_financials r
JOIN ref_quarter q ON q.report_date = r.REPDTE;

CREATE OR REPLACE TABLE stg_call_report_long AS
SELECT cert, report_date, field_code, value
FROM (
    UNPIVOT (SELECT * EXCLUDE (quarter_label, in_analysis_window, bank_name_as_reported)
             FROM stg_call_report)
    ON COLUMNS(* EXCLUDE (cert, report_date))
    INTO NAME field_code VALUE value
);

-- ---------------------------------------------------------------------------
-- Call Report income statement (Schedule RI) is reported year-to-date.
-- Q1 = YTD; Q2..Q4 = YTD(this quarter) - YTD(previous quarter, same year).
-- If the previous quarter is missing we leave the quarter NULL rather than
-- guess.
--
-- Simple subtraction breaks when a bank absorbs another charter mid-year (the
-- YTD base changes). FDIC publishes single-quarter values for the main lines
-- (NETINCQ, NIMQ, ...) that handle this, so:
--   quarter_value_derived  our YTD(q) - YTD(q-1)    -> tested against FDIC in check XP01
--   quarter_value          FDIC quarterly where published, else our derived value
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE ref_quarterly_control AS
SELECT * FROM (VALUES
    ('NETINC', 'NETINCQ'), ('NIM', 'NIMQ'), ('NONII', 'NONIIQ'),
    ('NONIX', 'NONIXQ'), ('ELNATR', 'ELNATQ'), ('NTLNLS', 'NTLNLSQ')
) t(field_code, ctrl_field);

CREATE OR REPLACE TABLE stg_income_quarterly AS
WITH ytd AS (
    SELECT l.cert, l.report_date, l.field_code, l.value AS ytd_value,
           year(l.report_date) AS yr, quarter(l.report_date) AS qtr
    FROM stg_call_report_long l
    JOIN ref_field f USING (field_code)
    WHERE f.period_type = 'ytd'
),
derived AS (
    SELECT
        cur.cert, cur.report_date, cur.field_code, cur.ytd_value,
        CASE WHEN cur.qtr = 1 THEN cur.ytd_value
             ELSE cur.ytd_value - prv.ytd_value
        END AS quarter_value_derived
    FROM ytd cur
    LEFT JOIN ytd prv
           ON prv.cert = cur.cert
          AND prv.field_code = cur.field_code
          AND prv.yr = cur.yr
          AND prv.qtr = cur.qtr - 1
)
SELECT
    d.cert, d.report_date, d.field_code, d.ytd_value, d.quarter_value_derived,
    c.value                                        AS quarter_value_fdic,
    coalesce(c.value, d.quarter_value_derived)     AS quarter_value,
    CASE WHEN c.value IS NOT NULL THEN 'FDIC quarterly' ELSE 'Derived from YTD' END AS quarter_value_source
FROM derived d
LEFT JOIN ref_quarterly_control m ON m.field_code = d.field_code
LEFT JOIN stg_call_report_long c
       ON c.cert = d.cert AND c.report_date = d.report_date AND c.field_code = m.ctrl_field;
