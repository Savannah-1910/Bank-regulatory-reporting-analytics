-- =============================================================================
-- 05_peer_benchmark.sql
-- Peer comparison: rank / percentile of every bank on every metric each quarter,
-- plus a scorecard for the focus bank (JPMorgan Chase Bank, N.A.).
--
--   fct_peer_benchmark   bank x quarter x metric with peer stats and percentile
--   fct_focus_scorecard  focus bank, latest quarter, one row per metric
--
-- Percentile convention: 100 = best in peer set, using ref_metric.higher_is_better
--   +1  higher value ranks better (capital ratios, ROE, ...)
--   -1  lower value ranks better (efficiency ratio, charge-offs, ...)
--    0  no "better" direction (size, loan-to-deposit) -> percentile of the raw value
-- =============================================================================

CREATE OR REPLACE TABLE fct_peer_benchmark AS
WITH m AS (
    SELECT l.*, b.short_name, b.bank_name, b.peer_group, b.is_focus_bank,
           CASE WHEN l.higher_is_better = -1 THEN -l.value ELSE l.value END AS score
    FROM fct_metrics_long l
    JOIN ref_bank b USING (cert)
    WHERE l.value IS NOT NULL
)
SELECT
    cert, short_name, bank_name, peer_group, is_focus_bank,
    report_date, quarter_label, merger_quarter,
    metric_code, metric_name, category, unit, higher_is_better,
    value,
    count(*)                         OVER w_all AS peer_count,
    median(value)                    OVER w_all AS peer_median,
    quantile_cont(value, 0.25)       OVER w_all AS peer_p25,
    quantile_cont(value, 0.75)       OVER w_all AS peer_p75,
    min(value)                       OVER w_all AS peer_min,
    max(value)                       OVER w_all AS peer_max,
    median(value)                    OVER w_grp AS peer_group_median,
    value - median(value)            OVER w_all AS diff_vs_peer_median,
    rank()         OVER (PARTITION BY report_date, metric_code ORDER BY score DESC) AS peer_rank,
    round(100 * percent_rank() OVER (PARTITION BY report_date, metric_code ORDER BY score), 1)
                                              AS peer_percentile
FROM m
WINDOW
    w_all AS (PARTITION BY report_date, metric_code),
    w_grp AS (PARTITION BY report_date, metric_code, peer_group);


CREATE OR REPLACE TABLE fct_focus_scorecard AS
WITH latest AS (SELECT max(report_date) AS d FROM fct_peer_benchmark),
f AS (
    SELECT p.*,
           lag(value, 1) OVER (PARTITION BY metric_code ORDER BY report_date) AS value_prior_q,
           lag(value, 4) OVER (PARTITION BY metric_code ORDER BY report_date) AS value_prior_y,
           avg(peer_percentile) OVER (PARTITION BY metric_code ORDER BY report_date
                                      ROWS BETWEEN 7 PRECEDING AND CURRENT ROW) AS avg_percentile_8q
    FROM fct_peer_benchmark p
    WHERE p.cert = {focus_cert}
)
SELECT
    f.short_name, f.quarter_label, f.category, f.metric_code, f.metric_name, f.unit,
    f.higher_is_better,
    f.value, f.peer_median, f.peer_group_median, f.diff_vs_peer_median,
    f.peer_rank, f.peer_count, f.peer_percentile, round(f.avg_percentile_8q, 1) AS avg_percentile_8q,
    f.value - f.value_prior_q AS change_qoq,
    f.value - f.value_prior_y AS change_yoy,
    CASE
        WHEN f.higher_is_better = 0 THEN 'n/a'
        WHEN f.peer_percentile >= 75 THEN 'Top quartile'
        WHEN f.peer_percentile >= 50 THEN 'Above median'
        WHEN f.peer_percentile >= 25 THEN 'Below median'
        ELSE 'Bottom quartile'
    END AS standing
FROM f, latest
WHERE f.report_date = latest.d
ORDER BY CASE f.category WHEN 'Size' THEN 0 WHEN 'Capital' THEN 1 WHEN 'Profitability' THEN 2
                         WHEN 'Asset Quality' THEN 3 ELSE 4 END, f.metric_code;
