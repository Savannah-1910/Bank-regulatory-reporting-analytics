# Data Dictionary - FDIC Call Report fields

Source: FDIC BankFind Suite API (`/financials`). Dollar amounts are in **USD thousands** as published by FDIC.

97 fields extracted. `period_type` matters: income-statement fields in the Call Report are **year-to-date**, so they must be de-cumulated before any quarter-over-quarter comparison.

## Balance Sheet

| Field | Business name | Category | Period type | FDIC title |
|---|---|---|---|---|
| `ASSET` | Total assets | Assets | point_in_time | Total assets |
| `CHBAL` | Cash & balances due from depository institutions | Assets | point_in_time | CASH & DUE FROM DEPOSITORY INST |
| `FREPO` | Fed funds sold & reverse repos | Assets | point_in_time | FED FUNDS & REPOS SOLD |
| `SC` | Total securities (HTM + AFS + equity, net of HTM allowance) | Assets | point_in_time | SECURITIES |
| `SCHA` | Held-to-maturity securities | Assets | point_in_time | SECURITIES-HA |
| `SCAF` | Available-for-sale securities | Assets | point_in_time | SECURITIES-AF |
| `SCEQFV` | Equity securities w/ readily determinable fair value | Assets | point_in_time | EQ SEC READILY DET FV |
| `SCHTMRES` | Allowance for credit losses on HTM securities | Assets | point_in_time | LESS ALLOW FOR CREDIT LOSSES ON HELD TO MATURITY DEBT SECURITIES |
| `TRADE` | Trading assets | Assets | point_in_time | TRADING ACCOUNTS |
| `LNLSGR` | Gross loans & leases | Loans | point_in_time | LOANS AND LEASES-TOTAL |
| `UNINC` | Unearned income | Loans | point_in_time | UNEARNED INCOME |
| `LNATRES` | Allowance for credit losses (loans) | Loans | point_in_time | ALLOW FOR LOANS LOSS ADJUSTED |
| `LNLSNET` | Net loans & leases | Assets | point_in_time | LOANS AND LEASES-NET |
| `BKPREM` | Premises & fixed assets | Assets | point_in_time | PREMISES AND FIXED ASSETS |
| `ORE` | Other real estate owned | Assets | point_in_time | OTHER REAL ESTATE OWNED |
| `INTAN` | Intangible assets | Assets | point_in_time | INTANGIBLE ASSETS |
| `INTANGW` | Goodwill | Assets | point_in_time | GOODWILL |
| `AOA` | All other assets | Assets | point_in_time | ALL OTH ASSETS |
| `ERNAST` | Total earning assets | Assets | point_in_time | TOTAL EARNING ASSETS |
| `LNRE` | Real estate loans | Loans | point_in_time | RE LOANS |
| `LNREDOM` | Real estate loans - domestic offices | Loans | point_in_time | RE LOANS-DOM |
| `LNREFOR` | Real estate loans - foreign offices | Loans | point_in_time | RE LOANS-FOR |
| `LNRECONS` | Construction & land development loans | Loans | point_in_time | RE CONSTRUCTION & LAND DEVELOP |
| `LNREAG` | Farmland loans | Loans | point_in_time | RE AGRICULTURAL |
| `LNRERES` | 1-4 family residential mortgages | Loans | point_in_time | RE 1-4 FAMILY |
| `LNREMULT` | Multifamily loans | Loans | point_in_time | RE MULTIFAMILY |
| `LNRENRES` | Non-farm non-residential CRE loans | Loans | point_in_time | RE NONFARM NONRESIDENTIAL PROP |
| `LNCI` | C&I loans | Loans | point_in_time | C&I LOANS |
| `LNCON` | Consumer loans | Loans | point_in_time | CONSUMER LOANS |
| `LNCRCD` | Credit card loans | Loans | point_in_time | CONSUMER LOANS-CREDIT CARD PLAN |
| `LNAUTO` | Auto loans | Loans | point_in_time | CONSUMER LOANS - AUTO |
| `LNCONRP` | Other revolving consumer loans | Loans | point_in_time | CONSUMER LNS-RELATED PLANS |
| `LNCONOTH` | Other consumer loans | Loans | point_in_time | CONSUMER LOANS-OTHER |
| `LNAG` | Agricultural loans | Loans | point_in_time | AGRICULTURAL LOANS |
| `LNDEP` | Loans to depository institutions | Loans | point_in_time | DEP INSTITUTION LOANS |
| `LNMUNI` | Loans to states & municipalities | Loans | point_in_time | MUNI LOANS |
| `LNFG` | Loans to foreign governments | Loans | point_in_time | FOREIGN GOVT LOANS |
| `LS` | Lease financing receivables | Loans | point_in_time | LEASES |
| `LNSOTHER` | All other loans | Loans | point_in_time | OTHER LOANS |
| `LNLSSALE` | Loans held for sale | Loans | point_in_time | LOANS & LEASES HELD FOR RESALE |
| `LIAB` | Total liabilities | Liabilities | point_in_time | TOTAL LIABILITIES |
| `DEP` | Total deposits | Deposits | point_in_time | Total deposits |
| `DEPDOM` | Deposits - domestic offices | Deposits | point_in_time | Deposits held in domestic offices |
| `DEPFOR` | Deposits - foreign offices | Deposits | point_in_time | TOTAL DEPOSITS-FOR |
| `DEPIDOM` | Interest-bearing domestic deposits | Deposits | point_in_time | INTEREST-BEARING DEP-DOM |
| `DEPNIDOM` | Noninterest-bearing domestic deposits | Deposits | point_in_time | NONINTEREST-BEARING DEP-DOM |
| `DEPINS` | Estimated insured deposits | Deposits | point_in_time | ESTIMATED INSURED DEPOSITS |
| `DEPUNINS` | Estimated uninsured deposits | Deposits | point_in_time | ESTIMATED UNINSURED DEPOSITS IN DOMESTIC OFFICES AND IN INSURED BRANCHES IN US TERRITORIES AND POSSESSIONS |
| `FREPP` | Fed funds purchased & repos | Liabilities | point_in_time | FED FUNDS & REPOS PURCHASED |
| `TRADEL` | Trading liabilities | Liabilities | point_in_time | TRADING LIABILITIES |
| `OTHBRF` | Other borrowed funds | Liabilities | point_in_time | OTH BORROWED FUNDS |
| `SUBND` | Subordinated notes & debentures | Liabilities | point_in_time | SUBORDINATED NOTES & DEBENTURES |
| `ALLOTHL` | All other liabilities | Liabilities | point_in_time | ALL OTHER LIABILITIES |
| `EQTOT` | Total equity capital (incl. minority interest) | Equity | point_in_time | TOTAL EQUITY CAPITAL |
| `EQ` | Bank equity capital | Equity | point_in_time | Equity capital |
| `EQCONSUB` | Minority interest in consolidated subs | Equity | point_in_time | MINOR INT IN CONSOL SUBS-EQ |

## Asset Quality

| Field | Business name | Category | Period type | FDIC title |
|---|---|---|---|---|
| `P3ASSET` | Loans 30-89 days past due | Delinquency | point_in_time | 30-89 DAYS P/D-TOTAL ASSETS |
| `P9ASSET` | Loans 90+ days past due | Delinquency | point_in_time | 90+ DAYS P/D-TOTAL ASSETS |
| `NAASSET` | Nonaccrual assets | Delinquency | point_in_time | NONACCRUAL-TOTAL ASSETS |
| `NCLNLS` | Noncurrent loans & leases | Delinquency | point_in_time | TOTAL N/C-LOANS & LEASES |
| `DRLNLS` | Gross charge-offs (YTD) | Charge-offs | ytd | TOTAL LN&LS CHARGE-OFFS |
| `CRLNLS` | Recoveries (YTD) | Charge-offs | ytd | TOTAL LN&LS RECOVERIES |
| `NTLNLS` | Net charge-offs (YTD) | Charge-offs | ytd | TOTAL LN&LS NET CHARGE-OFFS |
| `NTLNLSQ` | Net charge-offs (quarter, FDIC) | Control | quarterly | TOTAL LN&LS NET CHARGE-OFFS QUARTERLY |

## Regulatory Capital

| Field | Business name | Category | Period type | FDIC title |
|---|---|---|---|---|
| `RBCT1C` | Common equity tier 1 capital | Capital | point_in_time | RC-R COMMON EQ TIER 1 CAPITAL |
| `RBCT1J` | Tier 1 capital | Capital | point_in_time | TIER 1 RBC ADJUSTED LLR - PCA |
| `RBCT2` | Tier 2 capital | Capital | point_in_time | RBC-TIER2-PCA |
| `RWAJ` | Risk-weighted assets | Capital | point_in_time | RWA-ADJUST-PCA-T1 & CET1 RATIO |

## Income Statement

| Field | Business name | Category | Period type | FDIC title |
|---|---|---|---|---|
| `INTINC` | Total interest income (YTD) | Revenue | ytd | TOTAL INTEREST INCOME |
| `EINTEXP` | Total interest expense (YTD) | Expense | ytd | TOTAL INTEREST EXPENSE |
| `NIM` | Net interest income (YTD) | Revenue | ytd | NET INTEREST INCOME |
| `NONII` | Noninterest income (YTD) | Revenue | ytd | TOTAL NONINTEREST INCOME |
| `NONIX` | Noninterest expense (YTD) | Expense | ytd | TOTAL NONINTEREST EXPENSE |
| `ELNATR` | Provision for credit losses (YTD) | Expense | ytd | PROVISIONS FOR CREDIT LOSSES |
| `IGLSEC` | Realized gains/losses on securities (YTD) | Revenue | ytd | SECURITIES GAINS AND LOSSES |
| `IBEFTAX` | Income before taxes (YTD) | Profit | ytd | INCOME BEFORE INC TAXES & DISC |
| `ITAX` | Income taxes (YTD) | Expense | ytd | APPLICABLE INCOME TAXES |
| `EXTRA` | Discontinued operations, net (YTD) | Profit | ytd | NET DISCONTINUED OPERATIONS |
| `NETIMIN` | Net income attributable to minority interest (YTD) | Profit | ytd | NET INC - ATTRIB TO MINORITY INT |
| `NETINC` | Net income (YTD) | Profit | ytd | Net income |
| `NETINCQ` | Net income (quarter, FDIC) | Control | quarterly | Net income - quarterly |
| `NIMQ` | Net interest income (quarter, FDIC) | Control | quarterly | NET INTEREST INCOME QUARTERLY |
| `NONIIQ` | Noninterest income (quarter, FDIC) | Control | quarterly | TOTAL NONINTEREST INCOME-QTR |
| `NONIXQ` | Noninterest expense (quarter, FDIC) | Control | quarterly | TOTAL NONINTEREST EXPENSE QUARTERLY |
| `ELNATQ` | Provision for credit losses (quarter, FDIC) | Control | quarterly | PROVISIONS FOR CREDIT LOSSES QUARTERLY |

## Ratios

| Field | Business name | Category | Period type | FDIC title |
|---|---|---|---|---|
| `RBC1AAJ` | Tier 1 leverage ratio (FDIC) | Capital | ratio_pct | LEVERAGE RATIO-PCA |
| `IDT1CER` | CET1 ratio (FDIC) | Capital | ratio_pct | COMMON EQUITY TIER 1 CAPITAL RATIO |
| `IDT1RWAJR` | Tier 1 risk-based capital ratio (FDIC) | Capital | ratio_pct | TIER 1 RISK-BASED CAPITAL RATIO |
| `RBCRWAJ` | Total risk-based capital ratio (FDIC) | Capital | ratio_pct | TOTAL RBC RATIO-PCA |
| `NIMY` | Net interest margin, YTD annualized (FDIC) | Profitability | ratio_pct | NET INTEREST MARGIN |
| `ROA` | Return on assets, YTD annualized (FDIC) | Profitability | ratio_pct | Return on assets (ROA) |
| `ROE` | Return on equity, YTD annualized (FDIC) | Profitability | ratio_pct | Return on Equity (ROE) |
| `EEFFR` | Efficiency ratio, YTD (FDIC) | Profitability | ratio_pct | EFFICIENCY RATIO |
| `NTLNLSR` | Net charge-off rate, YTD annualized (FDIC) | Asset Quality | ratio_pct | NET CHARGE-OFFS/LOANS & LEASES |
| `NCLNLSR` | Noncurrent loans / gross loans (FDIC) | Asset Quality | ratio_pct | N/C LNS & LS/GROSS LNS & LS |
| `LNRESNCR` | Allowance / noncurrent loans (FDIC) | Asset Quality | ratio_pct | LOAN LOSS RESERVE/N/C LOANS |
| `LNLSDEPR` | Net loans / deposits (FDIC) | Liquidity | ratio_pct | NET LOANS & LEASES/DEPOSITS |
