"""Build a clean monthly dataset from the small trial spreadsheet.

Reads data/Fiscal_Macro_Dataset_trial_small.xlsx and writes:
  - data/trial_small_monthly.csv             (date + one column per mnemonic)
  - data/trial_small_monthly_dictionary.json (mnemonic -> source description / transform)

Variables are looked up by their source description string (the sheet has no
duplicate descriptions, unlike the full trial spreadsheet, so each series is
uniquely identifiable by name alone). Two transforms are applied where
needed:
  - "Q": series is quarterly but repeated across all 3 months of the quarter
         in the source file -> keep only the quarter-end (Mar/Jun/Sep/Dec)
         observation, set the other two months to NaN.
  - "C": series is a monthly year-to-date cumulative flow -> decumulate to a
         genuine monthly flow (first differences within each calendar year).
"""

from pathlib import Path
import json

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
RAW_PATH = REPO_ROOT / "data" / "Fiscal_Macro_Dataset_trial_small.xlsx"
OUT_DATA_PATH = REPO_ROOT / "data" / "trial_small_monthly.csv"
OUT_DICT_PATH = REPO_ROOT / "data" / "trial_small_monthly_dictionary.json"

HEADER_ROW = 3  # 0-based row index (in the raw sheet) holding variable descriptions
DATA_START_ROW = 4  # 0-based row index where the first observation appears

# (source description, mnemonic, transform)
# transform is one of "M" (use as-is), "Q" (dequarter), "C" (decumulate).
VARIABLES = [
    ('General Government Budget, Revenues, Taxes, Total, EUR', 'REV_GG_TAX_TOTAL_M', 'M'),
    ('Central Government Budget, Revenues, Total, Aggregate, EUR', 'REV_CG_TOTAL_M', 'C'),
    ('Central Government Budget, Expenditures, Total, Aggregate, EUR', 'EXP_CG_TOTAL_M', 'C'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, EUR', 'EXP_GG_SA_TOTAL_Q', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, EUR', 'REV_GG_SA_TOTAL_Q', 'Q'),
    ('Business Surveys, Ifo, Business Survey, Total, Business Climate, Average, SA (X-13 ARIMA), Index', 'IFO_BIZCLIMATE_M', 'M'),
    ('Implicit Price Deflator, Gross Domestic Product, Index', 'GDP_DEFLATOR_Q', 'Q'),
    ('Gross Domestic Product, Total, Real Terms, Constant Prices, Index', 'GDP_REAL_Q', 'Q'),
    ('Harmonized CPI, Total, Index', 'HICP_TOTAL_M', 'M'),
    ('Industrial Production, Total, Excluding Construction, Constant Prices, Index', 'IP_TOTAL_M', 'M'),
    ('Domestic Trade, Retail Trade, Turnover, Total, Excluding Vehicle Trade, Constant Prices, Index', 'RETAIL_TURNOVER_M', 'M'),
    ('Domestic Trade, Vehicle Sales & Registrations, New Registrations, Motor Vehicles, Passenger Cars', 'AUTO_SALES_M', 'M'),
    ('Government Benchmarks, Bundesbank, 10 Year, Yield, End of Period', 'BUND_YIELD_10Y_M', 'M'),
]

TRANSFORM_LABELS = {
    "M": "none (already monthly)",
    "Q": "dequarter (keep Mar/Jun/Sep/Dec, NaN elsewhere)",
    "C": "decumulate (year-to-date -> monthly flow)",
}


def dequarter(series: pd.Series) -> pd.Series:
    """Keep only the quarter-end (Mar/Jun/Sep/Dec) observation each quarter."""
    out = series.copy()
    out[~out.index.month.isin([3, 6, 9, 12])] = float("nan")
    return out


def decumulate(series: pd.Series) -> pd.Series:
    """Turn a year-to-date cumulative series into a monthly flow.

    The first observed month of each calendar year keeps its raw value (that
    value already is the flow for that month); every later month is replaced
    by the difference to the previous month.
    """
    values = series.to_numpy(dtype=float)
    years = series.index.year.to_numpy()

    flow = values.copy()
    flow[1:] = values[1:] - values[:-1]

    is_new_year = np.empty(len(years), dtype=bool)
    is_new_year[0] = True
    is_new_year[1:] = years[1:] != years[:-1]
    flow[is_new_year] = values[is_new_year]

    return pd.Series(flow, index=series.index)


def load_raw():
    raw = pd.read_excel(RAW_PATH, sheet_name=0, header=None)
    names = raw.iloc[HEADER_ROW, 1:].tolist()
    dates = pd.to_datetime(raw.iloc[DATA_START_ROW:, 0]).reset_index(drop=True)
    data = raw.iloc[DATA_START_ROW:, 1:].reset_index(drop=True)
    data.columns = range(data.shape[1])
    data.index = dates
    data = data.astype(float)
    return data, names


def build_dataset():
    data, names = load_raw()

    out_columns = {}
    dictionary = {}
    for source_name, mnemonic, transform in VARIABLES:
        col_idx = names.index(source_name)
        series = data[col_idx]
        if transform == "Q":
            series = dequarter(series)
        elif transform == "C":
            series = decumulate(series)
        out_columns[mnemonic] = series
        dictionary[mnemonic] = {
            "source_description": source_name,
            "transform": TRANSFORM_LABELS[transform],
        }

    out = pd.DataFrame(out_columns)
    out.index.name = "date"
    out = out.sort_index()

    return out, dictionary


def main():
    out, dictionary = build_dataset()
    out.to_csv(OUT_DATA_PATH)
    with open(OUT_DICT_PATH, "w") as f:
        json.dump(dictionary, f, indent=2)
    print(f"Wrote {out.shape[0]} rows x {out.shape[1]} variables to {OUT_DATA_PATH}")
    print(f"Wrote data dictionary ({len(dictionary)} entries) to {OUT_DICT_PATH}")


if __name__ == "__main__":
    main()
