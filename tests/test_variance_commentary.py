"""Unit tests for the commentary generator (run: python -m pytest tests)."""
import sys
from collections import namedtuple
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from variance_commentary import build_commentary, fmt_money, fmt_pct  # noqa: E402

Line = namedtuple("Line", "line_code line_name comparison change pct_change sign")
Parent = namedtuple("Parent", "line_name change")


def kids(*rows):
    return pd.DataFrame(rows, columns=["line_code", "line_name", "sign", "change"])


def test_fmt_money_billions_and_millions():
    assert fmt_money(12_034_000) == "+$12.0B"
    assert fmt_money(-850_000) == "-$850M"


def test_fmt_pct_not_meaningful():
    assert fmt_pct(None) == "n.m."
    assert fmt_pct(0.041) == "+4.1%"


def test_driver_and_offset():
    loans = Line("LNLSGR", "Gross loans", "QoQ", 20_000_000, 0.05, 1)
    children = kids(("LNCI", "C&I loans", 1, 12_000_000),
                    ("LNCON", "Consumer loans", 1, 11_000_000),
                    ("LNRE", "Real estate loans", 1, -3_000_000))
    text, driver, share = build_commentary(loans, children)
    assert text == ("Gross loans +5.0% QoQ (+$20.0B), driven by C&I loans +$12.0B and "
                    "consumer loans +$11.0B, partly offset by real estate loans -$3.0B.")
    assert driver == "LNCI"
    assert abs(share - 0.6) < 1e-9


def test_expense_child_is_described_as_higher_or_lower():
    ni = Line("NETINC_Q", "Net income", "QoQ", -1_300_000, -1.75, 1)
    children = kids(("NONIX_Q", "Noninterest expense", -1, 1_400_000),
                    ("NIM_Q", "Net interest income", 1, 50_000))
    text, driver, _ = build_commentary(ni, children)
    assert "driven by higher noninterest expense (+$1.4B)" in text
    assert driver == "NONIX_Q"


def test_leaf_line_references_parent_share():
    card = Line("LNCRCD", "Credit card loans", "QoQ", 2_000_000, 0.12, 1)
    text, driver, _ = build_commentary(card, kids(), Parent("Consumer loans", 4_000_000))
    assert "explains 50% of the +$4.0B move in consumer loans" in text
    assert driver is None
