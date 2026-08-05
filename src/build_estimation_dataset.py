"""Build the estimation dataset from the small trial dataset's monthly CSV.

Reads data/trial_small_monthly.csv and writes:
  - data/dataset_estimation.csv (date + one column per mnemonic, from 1996
    onwards -- SA/growth-rate transforms are computed on each series' full
    history first, then the output is truncated to this window)

The estimation transform applied to each mnemonic is documented back into the
existing data/trial_small_monthly_dictionary.json (as "estimation_seasonal_
adjustment" / "estimation_transform" fields alongside the raw-data fields
already there) rather than in a separate dictionary file.

Only the fiscal variables (government revenue/expenditure series) are
seasonally adjusted with X-13ARIMA-SEATS; the other macro series are already
seasonally adjusted at the source or have no seasonal pattern to remove.
Three groups of transforms are applied, at whichever frequency each series is
natively observed at:
  - FISCAL_VARIABLES: seasonally adjust with X-13ARIMA-SEATS, then take the
    growth rate (month-on-month for monthly series, quarter-on-quarter for
    quarterly series -- quarterly series are compressed to a true quarterly
    series for the X-13 step, then the growth rate is placed back on the
    monthly grid at the quarter-end month, NaN elsewhere)
  - FIRST_DIFF_ONLY (IFO_BIZCLIMATE, BUND_YIELD_10Y): first difference, no SA
  - everything else: growth rate (MoM or QoQ, as above), no SA

Which mnemonics are quarterly-native is read from
data/trial_small_monthly_dictionary.json (any variable whose transform there
is the "dequarter" transform).

Requires the X-13ARIMA-SEATS binary. This repo vendors it at
tools/x13as/x13as.exe (downloaded from
https://www2.census.gov/software/x-13arima-seats/x13as/windows/program-archives/),
which is passed to statsmodels via X13PATH.
"""

from pathlib import Path
import json

import pandas as pd
from statsmodels.tsa.x13 import x13_arima_analysis

REPO_ROOT = Path(__file__).resolve().parent.parent
IN_DATA_PATH = REPO_ROOT / "data" / "trial_small_monthly.csv"
DICT_PATH = REPO_ROOT / "data" / "trial_small_monthly_dictionary.json"
OUT_DATA_PATH = REPO_ROOT / "data" / "dataset_estimation.csv"

X13PATH = REPO_ROOT / "tools" / "x13as"

# SA/growth-rate transforms are computed on each series' full history (more
# data helps X-13's model fit), then the output is truncated to this date.
SAMPLE_START = pd.Timestamp("1996-01-01")

# Government revenue/expenditure series: the only ones seasonally adjusted.
FISCAL_VARIABLES = {
    "REV_GG_TAX_TOTAL",
    "REV_CG_TOTAL",
    "EXP_CG_TOTAL",
    "EXP_GG_SA_TOTAL",
    "REV_GG_SA_TOTAL",
}

# No seasonal adjustment: IFO_BIZCLIMATE is already SA at the source, and
# interest rates have no seasonal pattern. Both are first-differenced.
FIRST_DIFF_ONLY = {"IFO_BIZCLIMATE", "BUND_YIELD_10Y"}


def monthly_growth(series: pd.Series, seasonal_adjust: bool) -> pd.Series:
    """Take month-on-month % growth of a monthly series, optionally seasonally
    adjusting it first with X-13ARIMA-SEATS."""
    trimmed = series.dropna()
    if seasonal_adjust:
        trimmed.index.freq = "MS"
        trimmed = x13_arima_analysis(trimmed, x12path=str(X13PATH), prefer_x13=True).seasadj
    growth = trimmed.pct_change() * 100
    return growth.reindex(series.index)


def quarterly_growth(series: pd.Series, seasonal_adjust: bool) -> pd.Series:
    """Compress a dequartered monthly series to quarterly, take
    quarter-on-quarter % growth (optionally seasonally adjusting first with
    X-13ARIMA-SEATS), and place the result back on the monthly grid."""
    quarterly = series.dropna()
    if seasonal_adjust:
        quarterly.index.freq = "QS-" + quarterly.index[0].strftime("%b").upper()
        quarterly = x13_arima_analysis(quarterly, x12path=str(X13PATH), prefer_x13=True).seasadj
    growth = quarterly.pct_change() * 100
    return growth.reindex(series.index)


def first_difference(series: pd.Series) -> pd.Series:
    return series.diff()


def build_dataset(dictionary: dict):
    data = pd.read_csv(IN_DATA_PATH, index_col=0, parse_dates=True)

    out_columns = {}
    for mnemonic in data.columns:
        series = data[mnemonic]
        is_quarterly = dictionary[mnemonic]["transform"].startswith("dequarter")

        if mnemonic in FIRST_DIFF_ONLY:
            out_columns[mnemonic] = first_difference(series)
            dictionary[mnemonic]["estimation_seasonal_adjustment"] = "none"
            dictionary[mnemonic]["estimation_transform"] = "first difference (level change)"
            continue

        seasonal_adjust = mnemonic in FISCAL_VARIABLES
        sa_label = "X-13ARIMA-SEATS" if seasonal_adjust else "none (already SA at source / no seasonal pattern)"
        if is_quarterly:
            out_columns[mnemonic] = quarterly_growth(series, seasonal_adjust)
            growth_label = "quarter-on-quarter growth rate (%)"
        else:
            out_columns[mnemonic] = monthly_growth(series, seasonal_adjust)
            growth_label = "month-on-month growth rate (%)"
        dictionary[mnemonic]["estimation_seasonal_adjustment"] = sa_label
        dictionary[mnemonic]["estimation_transform"] = (
            f"{growth_label}, on seasonally adjusted series" if seasonal_adjust else growth_label
        )

    out = pd.DataFrame(out_columns)
    out.index.name = "date"
    out = out.loc[SAMPLE_START:]
    return out


def main():
    with open(DICT_PATH) as f:
        dictionary = json.load(f)

    out = build_dataset(dictionary)
    out.to_csv(OUT_DATA_PATH)
    with open(DICT_PATH, "w") as f:
        json.dump(dictionary, f, indent=2)
    print(f"Wrote {out.shape[0]} rows x {out.shape[1]} variables to {OUT_DATA_PATH}")
    print(f"Updated data dictionary ({len(dictionary)} entries) in {DICT_PATH}")


if __name__ == "__main__":
    main()
