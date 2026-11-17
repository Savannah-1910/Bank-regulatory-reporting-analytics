"""
Step 4b - Driver-based commentary for material variances.

For every material (flagged) variance in fct_variance we look at the line's
children in the roll-up (ref_line_item.parent_code) and write one sentence such as:

    "Net loans +4.1% QoQ (+$62.3B), driven by C&I loans +$12.0B and credit card
     loans +$8.1B, partly offset by a higher allowance for credit losses (+$1.2B)."

Logic
  * contribution of a child = sign x child change  (sign = -1 for contra / expense lines)
  * drivers  = children whose contribution has the same direction as the parent
               change; the largest one is always named, a second one only if it
               explains >= 10% of the parent move
  * offset   = the largest opposite-direction contributor, if >= 10% of the move
  * leaf lines (no Call Report breakdown) get a prompt for business input
  * if a merger / acquisition falls in the comparison window, we say so - the
    move is not organic and should not be explained as business growth

Output table: fct_variance_commentary (one row per flagged variance).
"""
import duckdb
import pandas as pd

from config import DB_PATH

MIN_DRIVER_SHARE = 0.10


def fmt_money(k: float, signed: bool = True) -> str:
    """$ thousands -> '+$12.0B' / '-$850M'."""
    sign = ("+" if k >= 0 else "-") if signed else ""
    a = abs(k)
    if a >= 1e6:
        return f"{sign}${a / 1e6:,.1f}B"
    return f"{sign}${a / 1e3:,.0f}M"


def fmt_pct(p) -> str:
    if p is None or pd.isna(p):
        return "n.m."
    return f"{p * 100:+.1f}%"


def child_phrase(row) -> str:
    """How to describe a child's move inside a sentence."""
    name = row.line_name
    if row.sign == -1:
        # contra/expense line: an increase hurts the parent
        direction = "higher" if row.change >= 0 else "lower"
        return f"{direction} {lower_first(name)} ({fmt_money(row.change)})"
    return f"{lower_first(name)} {fmt_money(row.change)}"


def lower_first(s: str) -> str:
    """'Noninterest income' -> 'noninterest income'; keep acronyms like 'C&I', 'HTM'."""
    return s if s[:2].isupper() or s[:1].isdigit() else s[:1].lower() + s[1:]


def build_commentary(parent, children: pd.DataFrame, parent_of=None) -> tuple[str, str | None, float | None]:
    """parent = the flagged line; children = its components; parent_of = the line it rolls up to."""
    head = f"{parent.line_name} {fmt_pct(parent.pct_change)} {parent.comparison} ({fmt_money(parent.change)})"

    if children.empty or parent.change == 0:
        if parent_of is not None and parent_of.change and not pd.isna(parent_of.change):
            share = parent.sign * parent.change / parent_of.change
            context = (f"explains {share:.0%} of the {fmt_money(parent_of.change)} move in "
                       if share > 0 else
                       f"moved against the {fmt_money(parent_of.change)} change in ")
            text = (head + f"; {context}{lower_first(parent_of.line_name)}. Lowest level in the "
                    "Call Report - obtain driver commentary from the business.")
        else:
            text = head + "; lowest level in the Call Report - obtain driver commentary from the business."
        return text, None, None

    ch = children.assign(contribution=children["sign"] * children["change"])
    same_dir = ch[ch["contribution"] * parent.change > 0].copy()
    opp_dir = ch[ch["contribution"] * parent.change < 0].copy()
    same_dir["share"] = same_dir["contribution"].abs() / abs(parent.change)
    opp_dir["share"] = opp_dir["contribution"].abs() / abs(parent.change)
    same_dir = same_dir.sort_values("share", ascending=False)
    opp_dir = opp_dir.sort_values("share", ascending=False)

    if same_dir.empty:
        text = head + "; no single component moved in the same direction."
        return text, None, None

    drivers = [same_dir.iloc[0]]
    if len(same_dir) > 1 and same_dir.iloc[1]["share"] >= MIN_DRIVER_SHARE:
        drivers.append(same_dir.iloc[1])
    text = head + ", driven by " + " and ".join(child_phrase(d) for d in drivers)

    if not opp_dir.empty and opp_dir.iloc[0]["share"] >= MIN_DRIVER_SHARE:
        text += ", partly offset by " + child_phrase(opp_dir.iloc[0])

    top = same_dir.iloc[0]
    return text + ".", top["line_code"], float(top["share"])


def main() -> None:
    with duckdb.connect(str(DB_PATH)) as con:
        var = con.sql("SELECT * FROM fct_variance").df()

        flagged = var[var["is_material"]]
        # children of every flagged parent, same bank / quarter / comparison
        kids = var[var["parent_code"].notna()]
        groups = {k: g for k, g in kids.groupby(["cert", "report_date", "comparison", "parent_code"])}
        lookup = {k: r for k, r in zip(
            zip(var["cert"], var["report_date"], var["comparison"], var["line_code"]),
            var[["line_name", "change"]].itertuples(index=False))}

        rows = []
        for p in flagged.itertuples(index=False):
            children = groups.get((p.cert, p.report_date, p.comparison, p.line_code), pd.DataFrame())
            if not children.empty:
                children = children[children["change"].notna()]
            parent_of = None
            if isinstance(p.parent_code, str):
                parent_of = lookup.get((p.cert, p.report_date, p.comparison, p.parent_code))
            text, driver, share = build_commentary(p, children, parent_of)
            if isinstance(p.structure_events, str) and p.structure_events:
                text += f" Note: bank {p.structure_events} - change includes acquired balances, not organic."
            rows.append({
                "cert": p.cert, "report_date": p.report_date, "comparison": p.comparison,
                "line_code": p.line_code, "commentary": text,
                "top_driver_code": driver, "top_driver_share": share,
                "is_inorganic": isinstance(p.structure_events, str) and bool(p.structure_events),
            })

        out = pd.DataFrame(rows, columns=["cert", "report_date", "comparison", "line_code", "commentary",
                                          "top_driver_code", "top_driver_share", "is_inorganic"])
        con.execute("CREATE OR REPLACE TABLE fct_variance_commentary AS SELECT * FROM out")

        # Final reporting table: every variance, with commentary where material
        con.execute("""
            CREATE OR REPLACE TABLE fct_variance_report AS
            SELECT v.*, c.commentary, c.top_driver_code,
                   d.line_name AS top_driver_name, c.top_driver_share,
                   coalesce(c.is_inorganic, FALSE) AS is_inorganic
            FROM fct_variance v
            LEFT JOIN fct_variance_commentary c
                   USING (cert, report_date, comparison, line_code)
            LEFT JOIN ref_line_item d ON d.line_code = c.top_driver_code
        """)
    print(f"  wrote commentary for {len(out):,} material variances "
          f"({out['is_inorganic'].sum():,} coincide with a merger/acquisition)")


if __name__ == "__main__":
    main()
