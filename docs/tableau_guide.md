# Tableau Public 搭建指南(3 页 dashboard)

数据都在 `output/tableau/`,重新跑一次 `python run_pipeline.py` 会覆盖这些文件。
金额单位都是 **$ millions**(列名带 `_mm`),比率单位都是 **%**。

> 这一步建议你自己动手做:面试官很可能问"你在 Tableau 里是怎么做的"。下面只给结构和关键步骤,具体的配色和排版由你决定。

---

## 0. 连接数据

每个 CSV 都已经带了银行简称(`short_name`)和 peer group,所以**不用建关系**:每个 CSV 单独作为一个数据源连接就行,更简单,也不容易出现重复计算。

1. Tableau Public → **Connect → To a File → Text file**,选 `peer_benchmark.csv`(第 1 页主要用它)。
2. 以后要用其他文件时,点 **Data → New Data Source → Text file** 再连一个。需要连的有:`focus_scorecard.csv`、`variance_analysis.csv`、`exception_report.csv`、`recon_rule_summary.csv`。
3. 检查数据类型:`report_date` 是 Date,`is_material` / `is_focus_bank` 是 Boolean,`pct_change` 是 Number。

建议建的计算字段:

| 名称 | 公式 | 用途 |
|---|---|---|
| `Bank Highlight` | `IF [short_name] = "JPM" THEN "JPM" ELSE "Peers" END` | 颜色:JPM 高亮,同业灰色(每个数据源都可以建) |
| `Pct Change Label` | `IF ISNULL([pct_change]) THEN "n.m." ELSE STR(ROUND([pct_change]*100,1)) + "%" END` | 差异表显示 |
| `Is Latest Quarter` | `[report_date] = {FIXED : MAX([report_date])}` | 默认只看最新季度 |

建议建的参数:
- `p_metric`(String,值来自 `peer_benchmark.metric_name`):让用户选要看的指标
- `p_bank`(String,默认 "JPM"):差异分析页选银行

---

## Page 1 — Overview(总览:JPM vs 同业)

| 图 | 数据 | 做法 |
|---|---|---|
| KPI 卡片 ×6 | `focus_scorecard` | CET1、Tier 1 leverage、ROE、NIM、NCO rate、Loan-to-deposit;每张卡显示 `value`、`peer_median`、`standing` |
| 趋势线 | `peer_benchmark` | Columns = `report_date`(季度),Rows = `value`;筛选 `metric_name = p_metric`;JPM 一条线,`peer_median` 做第二条线(Dual Axis 或 Measure Values) |
| 排名条形图 | `peer_benchmark` + `Is Latest Quarter` | 20 家银行横向条形,按 value 排序,颜色 = `Bank Highlight` 或 `peer_group` |
| 百分位热力图(可选) | `peer_benchmark` | Rows = `metric_name`,Columns = `quarter_label`,Color = `peer_percentile`,筛选 JPM,一眼看出哪些指标长期领先或落后 |

## Page 2 — Variance Analysis(差异分析)

| 图 | 数据 | 做法 |
|---|---|---|
| 筛选器 | `variance_analysis` | `short_name`(= p_bank)、`quarter_label`、`comparison`(QoQ/YoY)、`section`、只看 `is_material` |
| 差异明细表 | `variance_analysis` | Rows = `line_name`(按 `sort_order` 排序),列 = `prior_value_mm`、`value_mm`、`change_mm`、`Pct Change Label`;`is_material = True` 的行标红;**Tooltip 放 `commentary`** |
| 净利润桥(Waterfall) | `variance_analysis` 筛选 `parent_code = "NETINC_Q"` | 用 Gantt Bar + Running Total 做瀑布图,展示净利润 QoQ 变动由哪些科目构成 |
| 同业对比 | `variance_analysis` | 选一个科目(比如 Total deposits),横向条形显示 20 家银行同一季度的 `pct_change` |

## Page 3 — Exceptions(例外清单)

| 图 | 数据 | 做法 |
|---|---|---|
| 规则通过率 | `recon_rule_summary` | 条形图:`rule_id` × `pass_rate_pct`,颜色按 `category` |
| 严重程度汇总 | `exception_report` | Count by `severity` × `resolution_status`(Explained / Open) |
| 热力图 | `exception_report` | Rows = `short_name`,Columns = `quarter_label`,Color = 例外数量 |
| 例外明细表 | `exception_report` | `severity`、`rule_name`、`short_name`、`quarter_label`、`detail`、`structure_events`、`resolution_status` |

---

## 发布

1. **Dashboard → New Dashboard**,三页分别做成三个 dashboard,再用 **Story** 或者导航按钮(Navigation object)串起来。
2. Size 建议设成 **Fixed 1200 × 800**,在 Tableau Public 上显示最稳定。
3. **File → Save to Tableau Public**,发布后把链接填进 README 的 "Tableau Public dashboard" 那一行,同时放到简历和 LinkedIn。

`variance_analysis.csv` 大约 9 万行。如果打开慢,可以在数据源页加 Extract filter,比如只保留 `report_date >= 2022-03-31`。
