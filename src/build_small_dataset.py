"""Build a clean monthly dataset from the small trial spreadsheets.

Reads data/Fiscal_Macro_Dataset_trial_small.xlsx (monthly series) and
data/Fiscal_Macro_Dataset_trial_small_quarterly.xlsx (quarterly series -- the
source now ships these in a separate file instead of repeating each
quarterly value across all 3 months of a combined monthly sheet) and writes:
  - data/trial_small_monthly.csv             (date + one column per mnemonic)
  - data/trial_small_monthly_dictionary.json (mnemonic -> source description /
    decumulate)

Variables are looked up by their source description string within whichever
file their transform says they live in (neither sheet has duplicate
descriptions, so each series is uniquely identifiable by name alone). Two
transforms are applied where needed:
  - "Q": series is quarterly, one row per quarter, dated at the first month
         of the quarter (Jan/Apr/Jul/Oct) in the source file -> relabel onto
         the quarter-end month (Mar/Jun/Sep/Dec) convention used for
         quarterly series elsewhere in this dataset; the other two months of
         the quarter are simply absent (become NaN once merged onto the
         monthly grid). Not recorded as its own dictionary field since it's
         already implied by the mnemonic's _Q suffix.
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
RAW_PATH_MONTHLY = REPO_ROOT / "data" / "Fiscal_Macro_Dataset_trial_small.xlsx"
RAW_PATH_QUARTERLY = REPO_ROOT / "data" / "Fiscal_Macro_Dataset_trial_small_quarterly.xlsx"
OUT_DATA_PATH = REPO_ROOT / "data" / "trial_small_monthly.csv"
OUT_DICT_PATH = REPO_ROOT / "data" / "trial_small_monthly_dictionary.json"

HEADER_ROW = 3  # 0-based row index (in the raw sheet) holding variable descriptions
DATA_START_ROW = 4  # 0-based row index where the first observation appears

# (source description, mnemonic, transform, publication_delay)
# transform is one of "M" (use as-is), "Q" (requarter), "C" (decumulate).
# publication_delay is in days after the end of the reference period:
#   REV/EXP _M    : given (20d, monthly fiscal cash-budget releases)
#   REV/EXP _Q    : looked up -- Destatis's "detailed" quarterly sector
#                   accounts results, released ~t+55 (matches the "Detailed"
#                   label in the source description; the EU/Eurostat
#                   transmission deadline is a slower t+85-112)
#   IFO_BIZCLIMATE: given (25d)
#   GDP_DEFLATOR_Q: given (45d)
#   GDP_REAL_Q    : given (30d)
#   GDP_NOMINAL_Q : assumed same as GDP_REAL_Q -- both released in the same
#                   Destatis national-accounts release
#   HICP_TOTAL_M  : looked up -- final CPI published "by the middle of the
#                   following month" (Destatis); source description now
#                   points at the Bundesbank national CPI, overall index,
#                   rather than the old Eurostat-harmonized HICP, since the
#                   source sheet only carries the former -- mnemonic kept
#                   unchanged for continuity
#   CPI_CORE_M    : assumed same release schedule as HICP_TOTAL_M (published
#                   together)
#   IP_TOTAL_M    : looked up -- e.g. Oct 2025 production data published
#                   2025-12-08, a 38-day lag (Destatis press release)
#   NEW_ORDERS_MANUF_M : assumed same as IP_TOTAL_M -- both released together
#                   in Destatis's manufacturing turnover/orders release
#   RETAIL_TURNOVER_M : looked up -- e.g. Oct 2025 retail turnover published
#                   2025-11-28, a 28-day lag (Destatis press release)
#   AUTO_SALES_M  : looked up -- KBA new-registration press releases land on
#                   the 1st-7th of the following month (~3-7 day lag)
#   BUND_YIELD_10Y: given (1d)
#   EXP_BA_TOTAL_M / REV_BA_CONTRIB_M : assumed same as REV/EXP_CG_TOTAL_M
#                   (20d) -- monthly Bundesbank public-finance cash
#                   statistics, same reporting cadence as the central
#                   government budget series; unlike those two, plotted
#                   values are already genuine monthly flows (not YTD
#                   cumulative), so no decumulation is applied here
VARIABLES = [
    ('General Government Budget, Revenues, Taxes, Total, EUR', 'REV_GG_TAX_TOTAL_M', 'M', 20),
    ('Central Government Budget, Revenues, Total, Aggregate, EUR', 'REV_CG_TOTAL_M', 'C', 20),
    ('Central Government Budget, Expenditures, Total, Aggregate, EUR', 'EXP_CG_TOTAL_M', 'C', 20),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, EUR', 'EXP_GG_TOTAL_Q', 'Q', 55),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, EUR', 'REV_GG_TOTAL_Q', 'Q', 55),
    ('Business Surveys, Ifo, Business Survey, Total, Business Climate, Average, SA (X-13 ARIMA), Index', 'IFO_BIZCLIMATE_M', 'M', 25),
    ('Implicit Price Deflator, Gross Domestic Product, SA (X13 JDemetra+), Index', 'GDP_DEFLATOR_Q', 'Q', 45),
    ('Gross Domestic Product, Total, Calendar Adjusted (X13 JDemetra+), Constant Prices, SA (X13 JDemetra+), Chained, Index', 'GDP_REAL_Q', 'Q', 30),
    ('Gross Domestic Product, Total, Calendar Adjusted (X-13 ARIMA), Current Prices, SA (X-13 ARIMA), EUR', 'GDP_NOMINAL_Q', 'Q', 30),
    ('Bundesbank, Consumer Price Index, Consumer Price Index, Germany, Overall Index, Calendar Adjusted, SA, Index', 'HICP_TOTAL_M', 'M', 15),
    ('Bundesbank, Consumer Price Index, Germany, All-Items Excluding Energy & 01.1 Food Products, Calendar Adjusted, SA, Index', 'CPI_CORE_M', 'M', 15),
    ('Industrial Production, Total, Excluding Construction, Calendar Adjusted (X13 JDemetra+), Constant Prices, SA (X13 JDemetra+), Index', 'IP_TOTAL_M', 'M', 40),
    ('New Orders, Manufacturing, Total (Excluding Other Vehicle Construction), Calendar Adjusted (X13 JDemetra+), Constant Prices, SA (X13 JDemetra+), Index', 'NEW_ORDERS_MANUF_M', 'M', 40),
    ('Domestic Trade, Retail Trade, Turnover, Total, Excluding Vehicle Trade, Calendar Adjusted (X13 JDemetra+), Constant Prices, SA (X13 JDemetra+), Index', 'RETAIL_TURNOVER_M', 'M', 30),
    ('Domestic Trade, Vehicle Sales & Registrations, New Registrations, Motor Vehicles, Passenger Cars', 'AUTO_SALES_M', 'M', 5),
    ('Government Benchmarks, Bundesbank, 10 Year, Yield, End of Period', 'BUND_YIELD_10Y_M', 'M', 1),
    ('Bundesbank, Federal Employment Agency - Expenditure - Total, EUR', 'EXP_BA_TOTAL_M', 'M', 20),
    ('Bundesbank, Federal Employment Agency - Revenue - Contributions, EUR', 'REV_BA_CONTRIB_M', 'M', 20),
]

def requarter(series: pd.Series) -> pd.Series:
    """Relabel a quarter-start-dated series onto the quarter-end month.

    The quarterly source file dates each observation at the first month of
    the quarter (Jan/Apr/Jul/Oct); shift to the quarter-end month
    (Mar/Jun/Sep/Dec) to match the convention used for quarterly series
    elsewhere in this dataset.
    """
    out = series.copy()
    out.index = out.index + pd.DateOffset(months=2)
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


def load_raw(path):
    raw = pd.read_excel(path, sheet_name=0, header=None)
    names = raw.iloc[HEADER_ROW, 1:].tolist()
    dates = pd.to_datetime(raw.iloc[DATA_START_ROW:, 0]).reset_index(drop=True)
    data = raw.iloc[DATA_START_ROW:, 1:].reset_index(drop=True)
    data.columns = range(data.shape[1])
    data.index = dates
    data = data.astype(float)
    return data, names


def build_dataset():
    data_m, names_m = load_raw(RAW_PATH_MONTHLY)
    data_q, names_q = load_raw(RAW_PATH_QUARTERLY)

    out_columns = {}
    dictionary = {}
    for source_name, mnemonic, transform, publication_delay in VARIABLES:
        if transform == "Q":
            series = requarter(data_q[names_q.index(source_name)])
        else:
            series = data_m[names_m.index(source_name)]
            if transform == "C":
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
