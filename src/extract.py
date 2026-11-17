"""
Step 1a - Extract Call Report data from the FDIC BankFind Suite API.

  1. Find the most recent quarter available.
  2. Pick the TOP_N largest banks by total assets in that quarter.
  3. Pull every quarter from EXTRACT_START onward for those banks.
  4. Pull institution metadata (city, state, holding company).

Raw API responses are saved as JSON under data/raw/ so the load step is
reproducible without hitting the API again (and so we have an audit trail of
exactly what was received).
"""
import json
import time
from datetime import datetime, timezone

import requests

from config import (API_BASE, EXTRACT_START, FIELD_DICTIONARY_URL, FIELDS,
                    ID_FIELDS, RAW_DIR, TOP_N)

PAGE_SIZE = 10_000


def _get(endpoint: str, params: dict, retries: int = 4) -> dict:
    """GET with simple exponential backoff - the public API occasionally times out."""
    url = f"{API_BASE}/{endpoint}"
    for attempt in range(retries):
        try:
            r = requests.get(url, params=params, timeout=90)
            r.raise_for_status()
            return r.json()
        except requests.RequestException as exc:
            if attempt == retries - 1:
                raise
            wait = 2 ** attempt
            print(f"  request failed ({exc}); retrying in {wait}s")
            time.sleep(wait)


def _get_all(endpoint: str, params: dict) -> list[dict]:
    """Page through results until we have `totals.count` rows."""
    rows, offset = [], 0
    while True:
        payload = _get(endpoint, {**params, "limit": PAGE_SIZE, "offset": offset})
        batch = [item["data"] for item in payload["data"]]
        rows.extend(batch)
        total = payload["totals"]["count"]
        offset += len(batch)
        if offset >= total or not batch:
            return rows


def latest_report_date() -> str:
    payload = _get("financials", {"fields": "REPDTE", "sort_by": "REPDTE",
                                  "sort_order": "DESC", "limit": 1})
    return payload["data"][0]["data"]["REPDTE"]


def top_banks(repdte: str, n: int) -> list[dict]:
    payload = _get("financials", {"filters": f"REPDTE:{repdte}",
                                  "fields": "CERT,NAMEFULL,ASSET",
                                  "sort_by": "ASSET", "sort_order": "DESC",
                                  "limit": n})
    return [item["data"] for item in payload["data"]]


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    repdte = latest_report_date()
    print(f"Latest Call Report quarter available: {repdte}")

    universe = top_banks(repdte, TOP_N)
    certs = [b["CERT"] for b in universe]
    print(f"Top {TOP_N} banks by total assets:")
    for i, b in enumerate(universe, 1):
        print(f"  {i:>2}. {b['NAMEFULL']:<55} ${b['ASSET'] / 1e6:>8,.0f}B")

    cert_filter = " OR ".join(str(c) for c in certs)
    fields = ",".join(ID_FIELDS + list(FIELDS))
    financials = _get_all("financials", {
        "filters": f"CERT:({cert_filter}) AND REPDTE:[{EXTRACT_START} TO {repdte}]",
        "fields": fields,
        "sort_by": "REPDTE", "sort_order": "ASC",
    })
    print(f"Pulled {len(financials):,} bank-quarter records x {len(FIELDS)} fields")

    institutions = _get_all("institutions", {
        "filters": f"CERT:({cert_filter})",
        "fields": "CERT,NAME,CITY,STALP,NAMEHCR,BKCLASS,CHARTER,REGAGNT,ESTYMD,ACTIVE",
    })

    # Structure changes (mergers, failed-bank acquisitions, corporate reorganizations).
    # Used to explain cross-period breaks: a charter merger changes the YTD base and
    # makes the balance sheet jump, so these events are the first thing to check.
    #   810 = merger/absorption, 811 = acquisition of a failed institution,
    #   820 = corporate reorganization ("phantom" interim charter)
    history = _get_all("history", {
        "filters": (f"CERT:({cert_filter}) AND ORG_ROLE_CDE:FI AND "
                    f"CHANGECODE:(810 OR 811 OR 820) AND "
                    f"EFFDATE:[{EXTRACT_START[:4]}-01-01 TO {repdte[:4]}-12-31]"),
        "fields": "CERT,INSTNAME,EFFDATE,CHANGECODE,CHANGECODE_DESC,OUT_INSTNAME,OUT_CERT",
        "sort_by": "EFFDATE", "sort_order": "ASC",
    })
    print(f"Pulled {len(history)} structure-change events")

    # Universe rank as of the latest quarter
    for rank, b in enumerate(universe, 1):
        b["ASSET_RANK"] = rank

    manifest = {
        "extracted_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "api_base": API_BASE,
        "latest_report_date": repdte,
        "extract_start": EXTRACT_START,
        "top_n": TOP_N,
        "record_count": len(financials),
        "field_count": len(FIELDS),
    }

    (RAW_DIR / "financials.json").write_text(json.dumps(financials))
    (RAW_DIR / "institutions.json").write_text(json.dumps(institutions, indent=1))
    (RAW_DIR / "universe.json").write_text(json.dumps(universe, indent=1))
    (RAW_DIR / "structure_history.json").write_text(json.dumps(history, indent=1))
    (RAW_DIR / "manifest.json").write_text(json.dumps(manifest, indent=1))

    # FDIC field dictionary (for the data dictionary's official titles)
    try:
        yaml_text = requests.get(FIELD_DICTIONARY_URL, timeout=60).text
        (RAW_DIR / "risview_properties.yaml").write_text(yaml_text, encoding="utf-8")
    except requests.RequestException as exc:
        print(f"  could not download field dictionary: {exc}")

    print(f"Raw files written to {RAW_DIR}")


if __name__ == "__main__":
    main()
