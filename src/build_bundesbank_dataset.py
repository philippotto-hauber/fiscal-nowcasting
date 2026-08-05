"""Download macro/fiscal indicators from the Bundesbank SDMX web service.

Writes:
  - data/bundesbank_indicators_monthly.csv            (date + one column per mnemonic)
  - data/bundesbank_indicators_monthly_dictionary.csv  (mnemonic -> series key / description)

Each series is fetched from https://api.statistiken.bundesbank.de/rest/data/{flow}/{key}
as CSV and placed on a common monthly (month-start) date grid:
  - daily series   -> monthly average
  - monthly series -> used as-is
  - quarterly series -> value placed at the quarter-end month (Mar/Jun/Sep/Dec), NaN elsewhere
  - annual series    -> value placed at the year-end month (December), NaN elsewhere

Series keys were supplied and verified against the live API one at a time; see
SERIES below. STILL MISSING (not requested from the API yet): production in the
construction sector, turnover for industry, turnover for construction, orders
for construction. Add them to SERIES once available -- everything else (the
frequency handling, monthly placement, dictionary export) already supports
whatever combination of A/Q/M/D frequencies they turn out to be.
"""

import re
from pathlib import Path

import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DATA_PATH = REPO_ROOT / "data" / "bundesbank_indicators_monthly.csv"
OUT_DICT_PATH = REPO_ROOT / "data" / "bundesbank_indicators_monthly_dictionary.csv"

BASE_URL = "https://api.statistiken.bundesbank.de/rest/data"

SAMPLE_START = pd.Timestamp("1991-01-01")

# (flow, key, mnemonic)
# native frequency is inferred from the period format Bundesbank returns
# (YYYY / YYYY-QN / YYYY-MM / YYYY-MM-DD), no need to specify it here.
SERIES = [
    ("BBGFS1", "Q.BQ2180", "FISCAL_REV"),
    ("BBGFS1", "Q.BQ2190", "FISCAL_EXP"),
    ("BBNZ1", "Q.DE.Y.H.0000.A", "GDP_REAL"),
    ("BBNZ1", "Q.DE.S.I.0000.A", "GDP_DEFLATOR"),
    ("BBDP1", "M.DE.Y.VPI.C.A00000.I20.A", "CPI_HEADLINE"),
    ("BBDP1", "M.DE.Y.VPI.C.XE0110.I20.A", "CPI_CORE"),
    ("BBDE1", "M.DE.Y.BAA1.A2P100000.G.C.I21.A", "IP_EX_CONSTR"),
    ("BBDE1", "M.DE.Y.AEA1.A2P300000.F.C.I21.A", "ORDERS_IND"),
    ("BBDE1", "M.DE.Y.GUA1.N2G470000.A.V.I21.A", "RETAIL_SALES"),
    ("BBDE1", "M.DE.Y.KAA1.P2XC29000.KFZ.N.ABA.A", "CAR_REG"),
    ("BBXS1", "Q.DE.S.EUBUCS.MANU.MAN013.TT.PCT.I00", "CAPU_MANU"),
    ("BBSSY", "D.REN.EUR.A630.000000WT1010.A", "YIELD_10Y"),
]

_PERIOD_PATTERN = re.compile(r"^\d{4}(-(Q[1-4]|\d{2}(-\d{2})?))?$")


def fetch_raw(flow: str, key: str) -> tuple[pd.DataFrame, str]:
    """Download a series as CSV and split it into (period, value) rows + description.

    The response starts with a variable number of metadata rows (decimals, unit,
    source comments, etc.) before the actual period;value rows begin, so we scan
    for the first row whose first field looks like a period label rather than
    assuming a fixed number of header rows.
    """
    url = f"{BASE_URL}/{flow}/{key}?format=csv"
    raw = pd.read_csv(url, sep=";", header=None, encoding="utf-8-sig", dtype=str)

    description = raw.iat[1, 1] if raw.shape[0] > 1 else ""

    data_start = None
    for i, val in enumerate(raw[0]):
        if isinstance(val, str) and _PERIOD_PATTERN.match(val.strip()):
            data_start = i
            break
    if data_start is None:
        raise ValueError(f"Could not locate data rows for {flow}.{key}")

    df = raw.iloc[data_start:, :2].copy()
    df.columns = ["period", "value"]
    df["period"] = df["period"].str.strip()
    # "." marks a missing observation (e.g. non-trading days in daily series)
    df["value"] = pd.to_numeric(df["value"].str.replace(",", ".", regex=False), errors="coerce")
    df = df.dropna(subset=["value"]).reset_index(drop=True)
    return df, description


def _quarter_end_month(quarter: int) -> int:
    return quarter * 3


def to_monthly(df: pd.DataFrame) -> tuple[pd.Series, str]:
    """Place (period, value) rows onto a month-start date index.

    Returns the series plus a short label describing which placement rule was
    used, for the data dictionary.
    """
    sample = df["period"].iloc[0]

    if re.match(r"^\d{4}-\d{2}-\d{2}$", sample):
        dates = pd.to_datetime(df["period"])
        month_start = dates.values.astype("datetime64[M]")
        s = pd.Series(df["value"].values, index=pd.DatetimeIndex(month_start))
        return s.groupby(level=0).mean(), "daily -> monthly average"

    if re.match(r"^\d{4}-\d{2}$", sample):
        idx = pd.to_datetime(df["period"], format="%Y-%m")
        return pd.Series(df["value"].values, index=idx), "monthly (as published)"

    if re.match(r"^\d{4}-Q[1-4]$", sample):
        years = df["period"].str[:4].astype(int)
        quarters = df["period"].str[-1].astype(int)
        idx = [
            pd.Timestamp(y, _quarter_end_month(q), 1)
            for y, q in zip(years, quarters)
        ]
        return pd.Series(df["value"].values, index=pd.DatetimeIndex(idx)), (
            "quarterly -> quarter-end month (Mar/Jun/Sep/Dec), NaN elsewhere"
        )

    if re.match(r"^\d{4}$", sample):
        idx = [pd.Timestamp(int(y), 12, 1) for y in df["period"]]
        return pd.Series(df["value"].values, index=pd.DatetimeIndex(idx)), (
            "annual -> year-end month (December), NaN elsewhere"
        )

    raise ValueError(f"Unrecognized period format: {sample!r}")


def build_dataset():
    out_columns = {}
    dictionary_rows = []

    for flow, key, mnemonic in SERIES:
        raw, description = fetch_raw(flow, key)
        series, placement = to_monthly(raw)
        out_columns[mnemonic] = series
        dictionary_rows.append(
            {
                "mnemonic": mnemonic,
                "flow": flow,
                "key": key,
                "source_description": description,
                "monthly_placement": placement,
            }
        )

    out = pd.DataFrame(out_columns)

    full_index = pd.date_range(SAMPLE_START, out.index.max(), freq="MS")
    out = out.reindex(full_index)
    out.index.name = "date"

    dictionary = pd.DataFrame(dictionary_rows)
    return out, dictionary


def main():
    out, dictionary = build_dataset()
    out.to_csv(OUT_DATA_PATH)
    dictionary.to_csv(OUT_DICT_PATH, index=False)
    print(f"Wrote {out.shape[0]} rows x {out.shape[1]} variables to {OUT_DATA_PATH}")
    print(f"Wrote data dictionary ({len(dictionary)} entries) to {OUT_DICT_PATH}")


if __name__ == "__main__":
    main()
