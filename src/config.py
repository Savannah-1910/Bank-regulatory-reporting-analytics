"""
Project configuration: bank universe, Call Report fields, peer groups, thresholds.

All dollar amounts in the FDIC BankFind API are reported in THOUSANDS of USD.
We keep raw values in thousands in the staging layer and convert to $ millions
only in presentation tables (metrics / Tableau extracts).
"""
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parents[1]
RAW_DIR = ROOT / "data" / "raw"
DB_PATH = ROOT / "data" / "bank_reporting.duckdb"
SQL_DIR = ROOT / "sql"
OUTPUT_DIR = ROOT / "output"
TABLEAU_DIR = OUTPUT_DIR / "tableau"
DOCS_DIR = ROOT / "docs"

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------
API_BASE = "https://banks.data.fdic.gov/api"
# Official field dictionary (YAML). Used to pull FDIC titles into our data dictionary.
FIELD_DICTIONARY_URL = "https://api.fdic.gov/banks/docs/risview_properties.yaml"

# ---------------------------------------------------------------------------
# Scope
# ---------------------------------------------------------------------------
TOP_N = 20                      # largest banks by total assets at the latest quarter
EXTRACT_START = "20170331"      # pull 2017 so that 2018 quarters have a YoY comparison base
ANALYSIS_START = "2018-03-31"   # reporting window starts 2018Q1
FOCUS_CERT = 628                # JPMorgan Chase Bank, N.A. (FDIC certificate number)

# ---------------------------------------------------------------------------
# Peer groups (by FDIC CERT). The universe is chosen dynamically (top N by
# assets) - any bank not listed here falls into "Other".
# Ticker is the parent holding company ticker, used as a short label.
# ---------------------------------------------------------------------------
BANK_LABELS = {
    # cert: (short_name, peer_group)
    628:   ("JPM",   "Universal / Money-Center"),
    3510:  ("BAC",   "Universal / Money-Center"),
    7213:  ("C",     "Universal / Money-Center"),
    3511:  ("WFC",   "Universal / Money-Center"),
    6548:  ("USB",   "Super-Regional"),
    6384:  ("PNC",   "Super-Regional"),
    9846:  ("TFC",   "Super-Regional"),
    18409: ("TD US", "Super-Regional"),
    6672:  ("FITB",  "Super-Regional"),
    6560:  ("HBAN",  "Super-Regional"),
    16571: ("BMO US", "Super-Regional"),
    11063: ("FCNCA", "Super-Regional"),
    57957: ("CFG",   "Super-Regional"),
    588:   ("MTB",   "Super-Regional"),
    17534: ("KEY",   "Super-Regional"),
    4297:  ("COF",   "Consumer / Card"),
    27471: ("AXP",   "Consumer / Card"),
    57803: ("ALLY",  "Consumer / Card"),
    33124: ("GS",    "Investment Bank / Wealth"),
    32992: ("MS",    "Investment Bank / Wealth"),
    34221: ("MS PB", "Investment Bank / Wealth"),
    57450: ("SCHW",  "Investment Bank / Wealth"),
    639:   ("BK",    "Trust & Custody"),
    14:    ("STT",   "Trust & Custody"),
    913:   ("NTRS",  "Trust & Custody"),
}

# ---------------------------------------------------------------------------
# Variance (flux) materiality thresholds
# A line item is flagged only if BOTH conditions hold:
#   |% change| >= PCT  AND  |$ change| >= AMOUNT
# Using AND avoids two kinds of noise:
#   - big % moves on tiny balances (e.g. OREO +300% from $2M to $8M)
#   - big $ moves that are immaterial relative to a $4T balance sheet
# ---------------------------------------------------------------------------
VARIANCE_PCT_THRESHOLD = 0.10
VARIANCE_AMOUNT_THRESHOLD_K = 1_000_000   # $1B expressed in $ thousands

# ---------------------------------------------------------------------------
# Call Report fields to extract.
# code: (business_name, statement, category, period_type)
#   period_type:
#     point_in_time - balance as of quarter end
#     ytd           - year-to-date flow (Call Report income statement convention)
#     quarterly     - FDIC-derived single-quarter flow (used to verify our own de-cumulation)
#     ratio_pct     - ratio computed by FDIC, in percent
# ---------------------------------------------------------------------------
FIELDS = {
    # ---- Balance sheet: assets
    "ASSET":    ("Total assets", "Balance Sheet", "Assets", "point_in_time"),
    "CHBAL":    ("Cash & balances due from depository institutions", "Balance Sheet", "Assets", "point_in_time"),
    "FREPO":    ("Fed funds sold & reverse repos", "Balance Sheet", "Assets", "point_in_time"),
    "SC":       ("Total securities (HTM + AFS + equity, net of HTM allowance)", "Balance Sheet", "Assets", "point_in_time"),
    "SCHA":     ("Held-to-maturity securities", "Balance Sheet", "Assets", "point_in_time"),
    "SCAF":     ("Available-for-sale securities", "Balance Sheet", "Assets", "point_in_time"),
    "SCEQFV":   ("Equity securities w/ readily determinable fair value", "Balance Sheet", "Assets", "point_in_time"),
    "SCHTMRES": ("Allowance for credit losses on HTM securities", "Balance Sheet", "Assets", "point_in_time"),
    "TRADE":    ("Trading assets", "Balance Sheet", "Assets", "point_in_time"),
    "LNLSGR":   ("Gross loans & leases", "Balance Sheet", "Loans", "point_in_time"),
    "UNINC":    ("Unearned income", "Balance Sheet", "Loans", "point_in_time"),
    "LNATRES":  ("Allowance for credit losses (loans)", "Balance Sheet", "Loans", "point_in_time"),
    "LNLSNET":  ("Net loans & leases", "Balance Sheet", "Assets", "point_in_time"),
    "BKPREM":   ("Premises & fixed assets", "Balance Sheet", "Assets", "point_in_time"),
    "ORE":      ("Other real estate owned", "Balance Sheet", "Assets", "point_in_time"),
    "INTAN":    ("Intangible assets", "Balance Sheet", "Assets", "point_in_time"),
    "INTANGW":  ("Goodwill", "Balance Sheet", "Assets", "point_in_time"),
    "AOA":      ("All other assets", "Balance Sheet", "Assets", "point_in_time"),
    "ERNAST":   ("Total earning assets", "Balance Sheet", "Assets", "point_in_time"),
    # ---- Loan composition
    "LNRE":     ("Real estate loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNREDOM":  ("Real estate loans - domestic offices", "Balance Sheet", "Loans", "point_in_time"),
    "LNREFOR":  ("Real estate loans - foreign offices", "Balance Sheet", "Loans", "point_in_time"),
    "LNRECONS": ("Construction & land development loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNREAG":   ("Farmland loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNRERES":  ("1-4 family residential mortgages", "Balance Sheet", "Loans", "point_in_time"),
    "LNREMULT": ("Multifamily loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNRENRES": ("Non-farm non-residential CRE loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNCI":     ("C&I loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNCON":    ("Consumer loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNCRCD":   ("Credit card loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNAUTO":   ("Auto loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNCONRP":  ("Other revolving consumer loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNCONOTH": ("Other consumer loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNAG":     ("Agricultural loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNDEP":    ("Loans to depository institutions", "Balance Sheet", "Loans", "point_in_time"),
    "LNMUNI":   ("Loans to states & municipalities", "Balance Sheet", "Loans", "point_in_time"),
    "LNFG":     ("Loans to foreign governments", "Balance Sheet", "Loans", "point_in_time"),
    "LS":       ("Lease financing receivables", "Balance Sheet", "Loans", "point_in_time"),
    "LNSOTHER": ("All other loans", "Balance Sheet", "Loans", "point_in_time"),
    "LNLSSALE": ("Loans held for sale", "Balance Sheet", "Loans", "point_in_time"),
    # ---- Liabilities
    "LIAB":     ("Total liabilities", "Balance Sheet", "Liabilities", "point_in_time"),
    "DEP":      ("Total deposits", "Balance Sheet", "Deposits", "point_in_time"),
    "DEPDOM":   ("Deposits - domestic offices", "Balance Sheet", "Deposits", "point_in_time"),
    "DEPFOR":   ("Deposits - foreign offices", "Balance Sheet", "Deposits", "point_in_time"),
    "DEPIDOM":  ("Interest-bearing domestic deposits", "Balance Sheet", "Deposits", "point_in_time"),
    "DEPNIDOM": ("Noninterest-bearing domestic deposits", "Balance Sheet", "Deposits", "point_in_time"),
    "DEPINS":   ("Estimated insured deposits", "Balance Sheet", "Deposits", "point_in_time"),
    "DEPUNINS": ("Estimated uninsured deposits", "Balance Sheet", "Deposits", "point_in_time"),
    "FREPP":    ("Fed funds purchased & repos", "Balance Sheet", "Liabilities", "point_in_time"),
    "TRADEL":   ("Trading liabilities", "Balance Sheet", "Liabilities", "point_in_time"),
    "OTHBRF":   ("Other borrowed funds", "Balance Sheet", "Liabilities", "point_in_time"),
    "SUBND":    ("Subordinated notes & debentures", "Balance Sheet", "Liabilities", "point_in_time"),
    "ALLOTHL":  ("All other liabilities", "Balance Sheet", "Liabilities", "point_in_time"),
    # ---- Equity
    "EQTOT":    ("Total equity capital (incl. minority interest)", "Balance Sheet", "Equity", "point_in_time"),
    "EQ":       ("Bank equity capital", "Balance Sheet", "Equity", "point_in_time"),
    "EQCONSUB": ("Minority interest in consolidated subs", "Balance Sheet", "Equity", "point_in_time"),
    # ---- Asset quality (point in time)
    "P3ASSET":  ("Loans 30-89 days past due", "Asset Quality", "Delinquency", "point_in_time"),
    "P9ASSET":  ("Loans 90+ days past due", "Asset Quality", "Delinquency", "point_in_time"),
    "NAASSET":  ("Nonaccrual assets", "Asset Quality", "Delinquency", "point_in_time"),
    "NCLNLS":   ("Noncurrent loans & leases", "Asset Quality", "Delinquency", "point_in_time"),
    # ---- Regulatory capital
    "RBCT1C":   ("Common equity tier 1 capital", "Regulatory Capital", "Capital", "point_in_time"),
    "RBCT1J":   ("Tier 1 capital", "Regulatory Capital", "Capital", "point_in_time"),
    "RBCT2":    ("Tier 2 capital", "Regulatory Capital", "Capital", "point_in_time"),
    "RWAJ":     ("Risk-weighted assets", "Regulatory Capital", "Capital", "point_in_time"),
    # ---- Income statement (YTD, Call Report convention)
    "INTINC":   ("Total interest income (YTD)", "Income Statement", "Revenue", "ytd"),
    "EINTEXP":  ("Total interest expense (YTD)", "Income Statement", "Expense", "ytd"),
    "NIM":      ("Net interest income (YTD)", "Income Statement", "Revenue", "ytd"),
    "NONII":    ("Noninterest income (YTD)", "Income Statement", "Revenue", "ytd"),
    "NONIX":    ("Noninterest expense (YTD)", "Income Statement", "Expense", "ytd"),
    "ELNATR":   ("Provision for credit losses (YTD)", "Income Statement", "Expense", "ytd"),
    "IGLSEC":   ("Realized gains/losses on securities (YTD)", "Income Statement", "Revenue", "ytd"),
    "IBEFTAX":  ("Income before taxes (YTD)", "Income Statement", "Profit", "ytd"),
    "ITAX":     ("Income taxes (YTD)", "Income Statement", "Expense", "ytd"),
    "EXTRA":    ("Discontinued operations, net (YTD)", "Income Statement", "Profit", "ytd"),
    "NETIMIN":  ("Net income attributable to minority interest (YTD)", "Income Statement", "Profit", "ytd"),
    "NETINC":   ("Net income (YTD)", "Income Statement", "Profit", "ytd"),
    "DRLNLS":   ("Gross charge-offs (YTD)", "Asset Quality", "Charge-offs", "ytd"),
    "CRLNLS":   ("Recoveries (YTD)", "Asset Quality", "Charge-offs", "ytd"),
    "NTLNLS":   ("Net charge-offs (YTD)", "Asset Quality", "Charge-offs", "ytd"),
    # ---- FDIC quarterly versions (control totals for our YTD -> quarter de-cumulation)
    "NETINCQ":  ("Net income (quarter, FDIC)", "Income Statement", "Control", "quarterly"),
    "NIMQ":     ("Net interest income (quarter, FDIC)", "Income Statement", "Control", "quarterly"),
    "NONIIQ":   ("Noninterest income (quarter, FDIC)", "Income Statement", "Control", "quarterly"),
    "NONIXQ":   ("Noninterest expense (quarter, FDIC)", "Income Statement", "Control", "quarterly"),
    "ELNATQ":   ("Provision for credit losses (quarter, FDIC)", "Income Statement", "Control", "quarterly"),
    "NTLNLSQ":  ("Net charge-offs (quarter, FDIC)", "Asset Quality", "Control", "quarterly"),
    # ---- FDIC-reported ratios (used to cross-check our recomputed ratios)
    "RBC1AAJ":  ("Tier 1 leverage ratio (FDIC)", "Ratios", "Capital", "ratio_pct"),
    "IDT1CER":  ("CET1 ratio (FDIC)", "Ratios", "Capital", "ratio_pct"),
    "IDT1RWAJR": ("Tier 1 risk-based capital ratio (FDIC)", "Ratios", "Capital", "ratio_pct"),
    "RBCRWAJ":  ("Total risk-based capital ratio (FDIC)", "Ratios", "Capital", "ratio_pct"),
    "NIMY":     ("Net interest margin, YTD annualized (FDIC)", "Ratios", "Profitability", "ratio_pct"),
    "ROA":      ("Return on assets, YTD annualized (FDIC)", "Ratios", "Profitability", "ratio_pct"),
    "ROE":      ("Return on equity, YTD annualized (FDIC)", "Ratios", "Profitability", "ratio_pct"),
    "EEFFR":    ("Efficiency ratio, YTD (FDIC)", "Ratios", "Profitability", "ratio_pct"),
    "NTLNLSR":  ("Net charge-off rate, YTD annualized (FDIC)", "Ratios", "Asset Quality", "ratio_pct"),
    "NCLNLSR":  ("Noncurrent loans / gross loans (FDIC)", "Ratios", "Asset Quality", "ratio_pct"),
    "LNRESNCR": ("Allowance / noncurrent loans (FDIC)", "Ratios", "Asset Quality", "ratio_pct"),
    "LNLSDEPR": ("Net loans / deposits (FDIC)", "Ratios", "Liquidity", "ratio_pct"),
}

ID_FIELDS = ["CERT", "REPDTE", "NAMEFULL"]
