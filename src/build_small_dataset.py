"""Build a clean monthly dataset from the small trial spreadsheet.

Reads data/Fiscal_Macro_Dataset_trial_small.xlsx and writes:
  - data/trial_small_monthly.csv             (date + one column per mnemonic)
  - data/trial_small_monthly_dictionary.json (mnemonic -> source description /
    decumulate)

Variables are looked up by their source description string (the sheet has no
duplicate descriptions, unlike the full trial spreadsheet, so each series is
uniquely identifiable by name alone). Two transforms are applied where
needed:
  - "Q": series is quarterly but repeated across all 3 months of the quarter
         in the source file -> keep only the quarter-end (Mar/Jun/Sep/Dec)
         observation, set the other two months to NaN. Not recorded as its
         own dictionary field since it's already implied by the mnemonic's
         _Q suffix.
  - "C": series is a monthly year-to-date cumulative flow -> decumulate to a
         genuine monthly flow (first differences within each calendar year).
         Recorded as dictionary field "decumulate": true/false.

Also records "publication_delay": the typical number of days between the end
of a reference period and the statistical release covering it (i.e. how
stale a given real-time observation is), used for real-time nowcasting
timing. Values were either given directly or looked up from Destatis/
Eurostat release schedules -- see the VARIABLES table below for sources.
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

# (source description, mnemonic, transform, publication_delay)
# transform is one of "M" (use as-is), "Q" (dequarter), "C" (decumulate).
# publication_delay is in days after the end of the reference period:
#   REV/EXP _M    : given (20d, monthly fiscal cash-budget releases)
#   REV/EXP _Q    : looked up -- Destatis's "detailed" quarterly sector
#                   accounts results, released ~t+55 (matches the "Detailed"
#                   label in the source description; the EU/Eurostat
#                   transmission deadline is a slower t+85-112)
#   IFO_BIZCLIMATE: given (25d)
#   GDP_DEFLATOR_Q: given (45d)
#   GDP_REAL_Q    : given (30d)
#   HICP_TOTAL_M  : looked up -- final HICP published "by the middle of the
#                   following month" (Destatis)
#   IP_TOTAL_M    : looked up -- e.g. Oct 2025 production data published
#                   2025-12-08, a 38-day lag (Destatis press release)
#   RETAIL_TURNOVER_M : looked up -- e.g. Oct 2025 retail turnover published
#                   2025-11-28, a 28-day lag (Destatis press release)
#   AUTO_SALES_M  : looked up -- KBA new-registration press releases land on
#                   the 1st-7th of the following month (~3-7 day lag)
#   BUND_YIELD_10Y: given (1d)
VARIABLES = [
    ('General Government Budget, Revenues, Taxes, Total, EUR', 'REV_GG_TAX_TOTAL_M', 'M', 20),
    ('Central Government Budget, Revenues, Total, Aggregate, EUR', 'REV_CG_TOTAL_M', 'C', 20),
    ('Central Government Budget, Expenditures, Total, Aggregate, EUR', 'EXP_CG_TOTAL_M', 'C', 20),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, EUR', 'EXP_GG_TOTAL_Q', 'Q', 55),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, EUR', 'REV_GG_TOTAL_Q', 'Q', 55),
    ('Business Surveys, Ifo, Business Survey, Total, Business Climate, Average, SA (X-13 ARIMA), Index', 'IFO_BIZCLIMATE_M', 'M', 25),
    ('Implicit Price Deflator, Gross Domestic Product, Index', 'GDP_DEFLATOR_Q', 'Q', 45),
    ('Gross Domestic Product, Total, Real Terms, Constant Prices, Index', 'GDP_REAL_Q', 'Q', 30),
    ('Harmonized CPI, Total, Index', 'HICP_TOTAL_M', 'M', 15),
    ('Industrial Production, Total, Excluding Construction, Constant Prices, Index', 'IP_TOTAL_M', 'M', 40),
    ('Domestic Trade, Retail Trade, Turnover, Total, Excluding Vehicle Trade, Constant Prices, Index', 'RETAIL_TURNOVER_M', 'M', 30),
    ('Domestic Trade, Vehicle Sales & Registrations, New Registrations, Motor Vehicles, Passenger Cars', 'AUTO_SALES_M', 'M', 5),
    ('Government Benchmarks, Bundesbank, 10 Year, Yield, End of Period', 'BUND_YIELD_10Y_M', 'M', 1),
]

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
    for source_name, mnemonic, transform, publication_delay in VARIABLES:
        col_idx = names.index(source_name)
        series = data[col_idx]
        if transform == "Q":
            series = dequarter(series)
        elif transform == "C":
            series = decumulate(series)
        out_columns[mnemonic] = series
        dictionary[mnemonic] = {
            "source_description": source_name,
            "decumulate": transform == "C",
            "publication_delay": publication_delay,
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
