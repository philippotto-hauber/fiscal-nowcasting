"""Compute X-13ARIMA-SEATS seasonally adjusted LEVELS for the fiscal variables.

Reads data/trial_small_monthly.csv and writes:
  - data/fiscal_sa_levels.csv (date + one column per fiscal mnemonic, SA
    levels, full history -- no sample truncation; that is left to the MATLAB
    pipeline, which also computes growth rates and standardizes)

Only the 5 fiscal variables (government revenue/expenditure series) are
processed; every other series in the dataset is either already seasonally
adjusted at the source or has no seasonal pattern to remove, so MATLAB's
load_sa_data.m just passes those through unchanged rather than needing
anything from this script.

Quarterly-native series (EXP_GG_TOTAL_Q, REV_GG_TOTAL_Q) are compressed to a
true quarterly series for the X-13 step (X-13 needs a continuous frequency,
not a monthly grid with 2-out-of-3 months NaN), then the seasonally adjusted
levels are placed back on the monthly grid at the quarter-end month, NaN
elsewhere -- the same convention trial_small_monthly.csv already uses.

This replaces the old src/build_estimation_dataset.py: growth-rate/first-
difference transforms and standardization now happen in MATLAB
(src/f_growth_rates.m) so that the seasonal factor implied by
raw-level / SA-level is available there too, for reseasonalizing the model's
forecasts of EXP_GG_TOTAL_Q and REV_GG_TOTAL_Q back to unadjusted levels.

The dictionary is updated for all 13 mnemonics with two fields describing
that MATLAB-side transform:
  - "seasonally_adjust": true for the 5 fiscal variables, false otherwise.
  - "transform": "diff" for FIRST_DIFF_ONLY (already a rate/index, so
    f_growth_rates.m first-differences it instead of taking a growth rate),
    "percent change" for everything else, "level" for no transform (not
    currently used by any mnemonic).

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
OUT_DATA_PATH = REPO_ROOT / "data" / "fiscal_sa_levels.csv"

X13PATH = REPO_ROOT / "tools" / "x13as"

# Government revenue/expenditure series: the only ones seasonally adjusted.
FISCAL_VARIABLES = {
    "REV_GG_TAX_TOTAL_M",
    "REV_CG_TOTAL_M",
    "EXP_CG_TOTAL_M",
    "EXP_GG_TOTAL_Q",
    "REV_GG_TOTAL_Q",
}

# Already a rate/index, not a flow -- f_growth_rates.m first-differences
# these instead of taking a growth rate. Mirrors the MATLAB-side constant of
# the same name in src/f_growth_rates.m.
FIRST_DIFF_ONLY = {"IFO_BIZCLIMATE_M", "BUND_YIELD_10Y_M"}


def monthly_sa(series: pd.Series) -> pd.Series:
    trimmed = series.dropna()
    trimmed.index.freq = "MS"
    sa = x13_arima_analysis(trimmed, x12path=str(X13PATH), prefer_x13=True).seasadj
    return sa.reindex(series.index)


def quarterly_sa(series: pd.Series) -> pd.Series:
    """Compress a dequartered monthly series to quarterly, seasonally adjust,
    and place the result back on the monthly grid at the quarter-end month."""
    quarterly = series.dropna()
    quarterly.index.freq = "QS-" + quarterly.index[0].strftime("%b").upper()
    sa = x13_arima_analysis(quarterly, x12path=str(X13PATH), prefer_x13=True).seasadj
    return sa.reindex(series.index)


def build_sa_levels(dictionary: dict):
    data = pd.read_csv(IN_DATA_PATH, index_col=0, parse_dates=True)

    out_columns = {}
    for mnemonic in data.columns:
        dictionary[mnemonic].pop("estimation_transform", None)
        dictionary[mnemonic].pop("estimation_seasonal_adjustment", None)

        dictionary[mnemonic]["seasonally_adjust"] = mnemonic in FISCAL_VARIABLES
        dictionary[mnemonic]["transform"] = "diff" if mnemonic in FIRST_DIFF_ONLY else "percent change"

        if mnemonic not in FISCAL_VARIABLES:
            continue

        series = data[mnemonic]
        is_quarterly = mnemonic.endswith("_Q")
        out_columns[mnemonic] = quarterly_sa(series) if is_quarterly else monthly_sa(series)

    out = pd.DataFrame(out_columns)[[m for m in data.columns if m in FISCAL_VARIABLES]]
    out.index.name = "date"
    return out


def main():
    with open(DICT_PATH) as f:
        dictionary = json.load(f)

    out = build_sa_levels(dictionary)
    out.to_csv(OUT_DATA_PATH)
    with open(DICT_PATH, "w") as f:
        json.dump(dictionary, f, indent=2)
    print(f"Wrote {out.shape[0]} rows x {out.shape[1]} variables to {OUT_DATA_PATH}")
    print(f"Updated data dictionary in {DICT_PATH}")


if __name__ == "__main__":
    main()
