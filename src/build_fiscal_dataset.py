"""Build a clean monthly fiscal/macro dataset from the trial spreadsheet.

Reads data/Fiscal_Macro_Dataset_trial.xlsx and writes:
  - data/fiscal_macro_monthly.csv            (date + one column per mnemonic)
  - data/fiscal_macro_monthly_dictionary.csv (mnemonic -> source description / transform)

Variables are looked up by their source description string (the text in the
sheet's header row), not by column position, so the script keeps working if
the source system reorders or inserts columns. A handful of descriptions
appear more than once in the sheet (see resolve_series below); those are
resolved from the data itself rather than a hardcoded index.

Two transforms are applied where needed:
  - "Q": series is quarterly but repeated across all 3 months of the quarter
         in the source file -> keep only the quarter-end (Mar/Jun/Sep/Dec)
         observation, set the other two months to NaN.
  - "C": series is a monthly year-to-date cumulative flow -> decumulate to a
         genuine monthly flow (first differences within each calendar year).

Columns not listed in VARIABLES were dropped during data exploration because
they were exact duplicates of another column, or annual-frequency data
(repeated across all 12 months) with no monthly signal to offer.
"""

from pathlib import Path

import numpy as np
import pandas as pd

REPO_ROOT = Path(__file__).resolve().parent.parent
RAW_PATH = REPO_ROOT / "data" / "Fiscal_Macro_Dataset_trial.xlsx"
OUT_DATA_PATH = REPO_ROOT / "data" / "fiscal_macro_monthly.csv"
OUT_DICT_PATH = REPO_ROOT / "data" / "fiscal_macro_monthly_dictionary.csv"

HEADER_ROW = 3  # 0-based row index (in the raw sheet) holding variable descriptions
DATA_START_ROW = 4  # 0-based row index where the first observation appears

# (source description, mnemonic, transform)
# transform is one of "M" (use as-is), "Q" (dequarter), "C" (decumulate).
VARIABLES = [
    ('Public Debt, Central Government Debt, Total, EUR', 'DEBT_CG_TOTAL', 'M'),
    ('General Government Budget, Revenues, Taxes, Total, EUR', 'REV_GG_TAX_TOTAL', 'M'),
    ('Central Government Budget, Expenditures, Total, Estimated, EUR', 'EXP_CG_TOTAL_EST', 'M'),
    ('Central Government Budget, Revenues, Total, Estimated, EUR', 'REV_CG_TOTAL_EST', 'M'),
    ('Central Government Budget, Revenues, Tax Revenue, Total, Estimated, EUR', 'REV_CG_TAX_TOTAL_EST', 'M'),
    ('Central Government Budget, Financial Balance, Estimated Revenue from Coin as Source of Financing the Deficit, EUR', 'FIN_CG_COIN_EST', 'M'),
    ('Central Government Budget, Financial Balance, Estimated Net Borrowing as Source of Financing the Deficit, EUR', 'FIN_CG_NETBORROW_EST', 'M'),
    ('Central Government Budget, Financial Balance, Movements in Reserves, Estimated, EUR', 'FIN_CG_RESERVES_EST', 'M'),
    ('Unemployment, Rate, as a Percent of Civilian Labour Force, SA', 'UNEMPL_RATE', 'M'),
    ('State Government Budget, Revenues, Taxes, Joint Taxes, Wages Tax Before Partition, EUR', 'REV_SG_TAX_WAGES', 'M'),
    ('State Government Budget, Revenues, Taxes, Joint Taxes, Corporation Tax, EUR', 'REV_SG_TAX_CORP', 'M'),
    ('State Government Budget, Revenues, Taxes, Joint Taxes, Final Withholding Tax on Interest & Capital Gains, EUR', 'REV_SG_TAX_WITHHOLD', 'M'),
    ('State Government Budget, Revenues, Taxes, Joint Taxes, Assessed Income Tax, EUR', 'REV_SG_TAX_ASSESSED', 'M'),
    ('State Government Budget, Revenues, Taxes, Joint Taxes, Non-Assessed Taxes on Earnings, EUR', 'REV_SG_TAX_NONASSESSED', 'M'),
    ('Central Government Budget, Revenues, Tax Revenue, Assessed Income Tax as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_ASSESSED_FED', 'C'),
    ('Central Government Budget, Revenues, Total, Aggregate, EUR', 'REV_CG_TOTAL', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_FEDSHARE', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Personal & Corporate Income Taxes, Including Final Withholding Tax on Interest & Capital Gains, as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_INCTAX_FED', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Wages Tax as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_WAGES_FED', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Non-Assessed Taxes on Earnings as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_NONASSESSED_FED', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Final Withholding Tax on Interest & Capital Gains as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_WITHHOLD_FED', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Value Added Taxes (VAT) as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_VAT_FED', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Trade Tax Apportionment as Federal Share of Joint Taxes, Aggregate, EUR', 'REV_CG_TAX_TRADETAX_FED', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Supplementary Grants to States, Aggregate, EUR', 'REV_CG_TAX_SUPPGRANTS', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, EU Own Resources Based on Gross National Income, Aggregate, EUR', 'REV_CG_TAX_EUOWN_GNI', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, EU Own Resources Based on VAT, Aggregate, EUR', 'REV_CG_TAX_EUOWN_VAT', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Grants to States for Public Transport, Aggregate, EUR', 'REV_CG_TAX_GRANTS_TRANSPORT', 'C'),
    ('Central Government Budget, Revenues, Tax Revenue, Grants to States for Motor Vehicle Tax & Heavy Goods Vehicle Toll, Aggregate, EUR', 'REV_CG_TAX_GRANTS_MVTAX', 'C'),
    ('Central Government Budget, Revenues, Other Revenues, Revenue from Economic Activity, Aggregate, EUR', 'REV_CG_OTH_ECONACT', 'C'),
    ('Central Government Budget, Revenues, Other Revenues, Interest Revenue, Aggregate, EUR', 'REV_CG_OTH_INTEREST', 'C'),
    ('Central Government Budget, Revenues, Other Revenues, Loan Repayments, Holdings & Privatization Revenue, Aggregate, EUR', 'REV_CG_OTH_PRIVATIZATION', 'C'),
    ('Central Government Budget, Expenditures, By Function, General Public Services, Aggregate, EUR', 'EXP_CG_FUNC_GENSERV', 'C'),
    ('Central Government Budget, Expenditures, By Function, Education, Science, Research & Cultural Affairs, Aggregate, EUR', 'EXP_CG_FUNC_EDU', 'C'),
    ('Central Government Budget, Expenditures, By Function, Defence, Aggregate, EUR', 'EXP_CG_FUNC_DEFENSE', 'C'),
    ('Central Government Budget, Expenditures, By Function, Social Security, Family Youth Affairs & Labour Market Policy, Aggregate, EUR', 'EXP_CG_FUNC_SOCSEC', 'C'),
    ('Central Government Budget, Expenditures, By Function, Health, Environment, Sport & Recreation, Aggregate, EUR', 'EXP_CG_FUNC_HEALTH', 'C'),
    ('Central Government Budget, Expenditures, By Function, Housing, Urban Development, Regional Planning & Local Community Services, Aggregate, EUR', 'EXP_CG_FUNC_HOUSING', 'C'),
    ('Central Government Budget, Expenditures, By Function, Food, Agriculture & Forestry, Aggregate, EUR', 'EXP_CG_FUNC_AGRI', 'C'),
    ('Central Government Budget, Expenditures, By Function, Energy & Water Supply, Trade & Services, Aggregate, EUR', 'EXP_CG_FUNC_ENERGY', 'C'),
    ('Central Government Budget, Expenditures, By Function, Transport & Communication, Aggregate, EUR', 'EXP_CG_FUNC_TRANSPORT', 'C'),
    ('Central Government Budget, Expenditures, By Function, Financial Management, Aggregate, EUR', 'EXP_CG_FUNC_FINMGMT', 'C'),
    ('Central Government Budget, Expenditures, By Category, Interest Expenditures, Aggregate, EUR', 'EXP_CG_CAT_INTEREST', 'C'),
    ('Central Government Budget, Expenditures, By Category, Ongoing Grants & Subsidies, Aggregate, EUR', 'EXP_CG_CAT_GRANTS', 'C'),
    ('Central Government Budget, Expenditures, By Category, Human Resources Expenditures, Aggregate, EUR', 'EXP_CG_CAT_HR', 'C'),
    ('Central Government Budget, Expenditures, By Category, Operating Expenditures, Aggregate, EUR', 'EXP_CG_CAT_OPEX', 'C'),
    ('Central Government Budget, Expenditures, By Category, Investment Expenditures, Aggregate, EUR', 'EXP_CG_CAT_INVEST', 'C'),
    ('Central Government Budget, Expenditures, By Category, Fixed Asset Investment, Aggregate, EUR', 'EXP_CG_CAT_FIXEDASSET', 'C'),
    ('Central Government Budget, Expenditures, By Category, Financial Assistance, Aggregate, EUR', 'EXP_CG_CAT_FINASSIST', 'C'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, EUR', 'EXP_GG_SA_TOTAL', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, Compensation of Employees, EUR', 'EXP_GG_SA_COE', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, Gross Capital Formation, EUR', 'EXP_GG_SA_GFCF', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, Intermediate Consumption, EUR', 'EXP_GG_SA_INTERMED', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Expenditure, Social Benefits Other than Social Transfers in Kind, EUR', 'EXP_GG_SA_SOCBEN', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Net Lending/Net Borrowing, EUR', 'GG_SA_NETLENDING', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, EUR', 'REV_GG_SA_TOTAL', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, Levies, EUR', 'REV_GG_SA_LEVIES', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, Social Contributions, EUR', 'REV_GG_SA_SOCCONTRIB', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Revenue, Taxes, EUR', 'REV_GG_SA_TAXES', 'Q'),
    ('Sector Accounts, General Government, Detailed, Revenue & Expenditure & Net Lending/Net Borrowing, Social Benefits in Kind, EUR', 'EXP_GG_SA_SOCBENKIND', 'Q'),
    ('Employment, Total, Domestic Concept', 'EMPL_TOTAL', 'Q'),
    ('Employment, Employees, Total, Domestic Concept', 'EMPL_EMPLOYEES', 'Q'),
    ('Gross Domestic Product, Total, Current Prices, EUR', 'GDP_NOMINAL', 'Q'),
    ('Income Approach, Gross National Income, Net National Income, Aggregate Income, Corporate & Investment Income, Resident Concept, EUR', 'GNI_CORP_INV_INCOME', 'Q'),
    ('Income Approach, Gross National Income, Net National Income, Compensation of Employees, Resident Concept, EUR', 'GNI_COE', 'Q'),
    ('Productivity, Costs & Hours Worked, Hours Worked, Persons in Employment, Total (Domestic Concept)', 'HOURS_WORKED', 'Q'),
    ('Expenditure Approach, Final Consumption Expenditure, Households & NPISH, Total, Calendar Adjusted (X13 JDemetra+), Current Prices, SA (X13 JDemetra+), EUR', 'GDP_CONS_HH', 'Q'),
    ('Expenditure Approach, Final Consumption Expenditure, Government, Total, All, Calendar Adjusted (X13 JDemetra+), Current Prices, SA (X13 JDemetra+), EUR', 'GDP_CONS_GOV', 'Q'),
    ('Expenditure Approach, Gross Capital Formation, Total, Calendar Adjusted (X13 JDemetra+), Current Prices, SA (X13 JDemetra+), EUR', 'GDP_GFCF', 'Q'),
    ('Expenditure Approach, External Balance, Export, Total, Calendar Adjusted (X13 JDemetra+), Current Prices, SA (X13 JDemetra+), EUR', 'GDP_EXPORTS', 'Q'),
    ('Expenditure Approach, External Balance, Import, Total, Calendar Adjusted (X13 JDemetra+), Current Prices, SA (X13 JDemetra+), EUR', 'GDP_IMPORTS', 'Q'),
    ('Sector Accounts, General Government, Allocation of Primary Income, Resources, Taxes on Production & Imports, Receivable, EUR', 'REV_GG_SA_TAXPROD', 'Q'),
    ('Sector Accounts, General Government, Secondary Distribution of Income, Resources, Current Taxes on Income, Wealth, Etc., EUR', 'REV_GG_SA_TAXINCOME', 'Q'),
    ('Sector Accounts, General Government, Changes in Net Worth Due to Saving & Capital Transfers, Resources, Capital Transfers, EUR', 'REV_GG_SA_CAPTRANSFER_RES', 'Q'),
    ('Sector Accounts, General Government, Allocation of Primary Income, Uses, Subsidies, Total, Payable, EUR', 'EXP_GG_SA_SUBSIDIES', 'Q'),
    ('Sector Accounts, General Government, Secondary Distribution of Income, Uses, Other Current Transfers, EUR', 'EXP_GG_SA_OTHTRANSFER', 'Q'),
    ('Sector Accounts, General Government, Changes in Net Worth Due to Saving & Capital Transfers, Uses, Capital Transfers, EUR', 'EXP_GG_SA_CAPTRANSFER_USE', 'Q'),
    ('Sector Accounts, General Government, Allocation of Primary Income, Uses, Property Income, EUR', 'EXP_GG_SA_PROPINC_USE', 'Q'),
    ('Sector Accounts, General Government, Allocation of Primary Income, Resources, Property Income, EUR', 'REV_GG_SA_PROPINC_RES', 'Q'),
    ('Social Security Funds, Expenditures, Total, Aggregate, EUR', 'EXP_SSF_TOTAL', 'Q'),
    ('Social Security Funds, Revenues, Total, Aggregate, EUR', 'REV_SSF_TOTAL', 'Q'),
    ('Pension Insurance Fund, Revenues, Total, EUR', 'REV_PIF_TOTAL', 'Q'),
    ('Pension Insurance Fund, Expenditures, Total, EUR', 'EXP_PIF_TOTAL', 'Q'),
    ('Pension Insurance Fund, Revenues, Contributions, EUR', 'REV_PIF_CONTRIB', 'Q'),
    ('Pension Insurance Fund, Expenditures, Pension Payments, EUR', 'EXP_PIF_PENSIONS', 'Q'),
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


def _median_run_length(series: pd.Series) -> float:
    """Median length of runs of consecutive, near-identical values.

    Used only to break ties when a source description matches more than one
    column: a genuinely quarterly series has runs of ~3 (repeated across the
    3 months of a quarter), an annual series has runs of ~12.
    """
    vals = series.dropna().to_numpy()
    if len(vals) < 6:
        return np.inf
    runs = []
    start = 0
    for i in range(1, len(vals) + 1):
        if i == len(vals) or not np.isclose(vals[i], vals[start], rtol=1e-9, atol=1e-6):
            runs.append(i - start)
            start = i
    return float(np.median(runs))


def resolve_series(data: pd.DataFrame, names: list[str], target_name: str) -> tuple[pd.Series, int]:
    """Return the (series, column position) for a source description.

    Most descriptions are unique. A few appear twice in the source sheet:
    either as an exact duplicate column (data is identical, pick either), or
    as two vintages of the same series -- one updated quarterly, one only
    annually. In the latter case we keep the more frequently updated column
    (smaller median run length), since that's the one with real monthly/
    quarterly signal.
    """
    matches = [i for i, n in enumerate(names) if n == target_name]
    if not matches:
        raise KeyError(f"Source description not found in sheet: {target_name!r}")
    if len(matches) == 1:
        return data[matches[0]], matches[0]

    best = min(matches, key=lambda i: _median_run_length(data[i]))
    return data[best], best


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
    dictionary_rows = []
    for source_name, mnemonic, transform in VARIABLES:
        series, col_idx = resolve_series(data, names, source_name)
        if transform == "Q":
            series = dequarter(series)
        elif transform == "C":
            series = decumulate(series)
        out_columns[mnemonic] = series
        dictionary_rows.append(
            {
                "mnemonic": mnemonic,
                "source_column": col_idx,
                "source_description": source_name,
                "transform": TRANSFORM_LABELS[transform],
            }
        )

    out = pd.DataFrame(out_columns)
    out.index.name = "date"
    out = out.sort_index()

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
