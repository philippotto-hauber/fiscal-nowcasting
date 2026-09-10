# Project History

Running log of work on this repo, kept for continuity across Claude Code sessions.
Newest entries at the top. Update this file when a session wraps up a
meaningful chunk of work (new commits, a design decision, or an in-progress
state worth flagging for next time).

## In progress (uncommitted, as of 2026-09-10)

User replaced `data/Fiscal_Macro_Dataset_trial_small.xlsx` with a version
that restructures the source sheet, not just refreshes values: 13 source
columns became 18, several series were swapped for renamed/SA variants, and
3 new series appeared. Updated `src/build_small_dataset.py`'s `VARIABLES`
table accordingly and reran the two-step pipeline
(`build_small_dataset.py` -> `data/trial_small_monthly.csv` +
`data/trial_small_monthly_dictionary.json`, then
`build_fiscal_sa_levels.py` -> `data/fiscal_sa_levels.csv`). Both ran clean
(one routine X-13 spectrum-peak warning, same as always).
- **Resolves the previously-deferred SA discrepancy**: `GDP_REAL_Q` and
  `GDP_DEFLATOR_Q`'s new source descriptions explicitly say "Calendar
  Adjusted (X13 JDemetra+), SA" -- the raw yearly pattern flagged in the
  2026-09-08 entry below should be gone now that the source itself provides
  SA levels. Not yet re-verified visually; worth confirming next time
  `main.m` is run.
- Renamed/remapped (same mnemonic, new source_description +, for
  GDP_REAL_Q/GDP_DEFLATOR_Q, publication_delay unchanged since no new info):
  `GDP_REAL_Q`, `GDP_DEFLATOR_Q`, `IP_TOTAL_M`, `RETAIL_TURNOVER_M`.
  `HICP_TOTAL_M` also remapped, but its replacement is the Bundesbank
  national CPI overall index, not a Eurostat-harmonized HICP (the sheet no
  longer has one) -- kept the same mnemonic for continuity; flag if this
  substitution matters for the model.
- Added 5 new mnemonics with no prior counterpart: `GDP_NOMINAL_Q` (direct
  nominal GDP in EUR -- not yet wired into `main.m`, which still derives
  nominal GDP via `f_nominal_gdp.m` + a manual EUR anchor), `CPI_CORE_M`
  (ex energy & food), `NEW_ORDERS_MANUF_M`, `EXP_BA_TOTAL_M` /
  `REV_BA_CONTRIB_M` (Bundesbank Federal Employment Agency monthly
  expenditure/contribution-revenue, confirmed genuine flows not YTD
  cumulative, unlike `REV_CG_TOTAL_M`/`EXP_CG_TOTAL_M`). publication_delay
  for all 5 is an assumption (documented inline in
  `build_small_dataset.py`), not a looked-up value -- none of them feed the
  SA step (only the 5 fiscal mnemonics do) or `main.m` yet.
- None of the new series are referenced by `main.m` or the MATLAB model
  yet -- only the CSV/dictionary build step was rerun, per the user's
  request to regenerate the estimation CSV. Incorporating them into the
  model is separate follow-up work.

## In progress (uncommitted, as of 2026-09-08)

Cleaning up `main.m`'s postprocessing/plotting around the MCMC draws:
- Added `src/f_postprocess_draws.m`: reuses `f_nominal_gdp.m` to get an
  implied nominal-GDP index, rescales it onto EUR via a caller-supplied
  anchor (`options.anchor_ngdp_eur` in `main.m`, currently `1171696e6`), and
  computes the GG fiscal balance (`REV_GG_TOTAL_Q - EXP_GG_TOTAL_Q`, SA
  levels) as a % of that EUR nominal GDP, per MCMC draw.
  - **Anchor units matter**: must be raw EUR, matching
    `EXP_GG_TOTAL_Q`/`REV_GG_TOTAL_Q`'s units -- a first attempt supplied it
    in EUR millions and produced a nonsense ~-1,000,000%-of-GDP ratio. Fixed;
    current output is a plausible ~-1% median forecast.
- Deleted the old manual `fiscal_vars.png` plotting block and the old
  `plot_forecasts(...)` call in `main.m`. Added `src/plot_gdp_deficit.m`
  (real GDP q/q growth + balance-to-GDP, as a 2-tile fan-chart figure,
  `output/gdp_deficit.png`) and extracted the shared fan-chart-drawing
  helper into `src/f_plot_fan.m` (generalized to support a forecast-only fan
  with no history bridge, for the balance-to-GDP panel). `plot_forecasts.m`
  itself still exists and works but is no longer called from `main.m`.
- `f_reseasonalize.m`/`forecasts_nsa` deliberately kept in `main.m`
  (computed but currently unused by any plot) -- explicitly requested to
  stay for a later stage.
- Ran `main.m` end-to-end via MATLAB R2023a in batch mode (10,000 MCMC
  iterations, ~7 min) to confirm it works.
- **Open item, deferred, not yet fixed**: `GDP_REAL_Q`/`GDP_DEFLATOR_Q` are
  NOT actually seasonally adjusted, despite `data/trial_small_monthly_dictionary.json`'s
  `seasonally_adjust: false` implying (via `build_fiscal_sa_levels.py`'s
  assumption) that they're already SA at the source or have no seasonal
  pattern. Raw `GDP_REAL_Q` levels show an unmistakable repeating yearly
  pattern (peak Q4, trough Q2) and its source description carries no SA
  qualifier, unlike properly-SA-labeled series in this dataset. Only the 5
  fiscal mnemonics actually get X-13ARIMA-SEATS treatment. User said "nothing
  yet, just flagging awareness" -- revisit when it matters.
- Also worth remembering: the dictionary's `seasonally_adjust` field means
  "this pipeline seasonally-adjusts it" (true only for the 5 fiscal
  mnemonics), not "this series is/isn't seasonally adjusted" -- easy to
  misread the field name literally.

## Commit history summary

- **001615c** Add CLAUDE.md and HISTORY.md for cross-session project context
- **3c6841b** Add publication_delay metadata to fiscal/macro dictionary
- **6c50ef8** Refactor dictionary schema and add nominal GDP forecast function
- **2d32e09** Rebuild MATLAB pipeline around SA levels and add forecast reseasonalization
- **8d2a8ef** Plot monthly fiscal series alongside quarterly ones in fiscal_vars.png
- **1330390** Encode frequency in mnemonics; rework `load_data()` to return split M/Q outputs
- **9fa74d1** Add small-trial dataset pipeline: monthly build + SA/growth estimation dataset
- **f11eb84** temporary commit to start fresh
- **693fdaa** add script to download macro/fiscal indicators from Bundesbank SDMX API
- **cca8a89** add script to build monthly fiscal/macro dataset from trial spreadsheet
- **0d78c69** fix forecast plot: datetime axes, correct quarter labeling, and per-variable Hq
- **01afce3** add fiscal variables (revenues and expenditures) to dataset
- **34de147** extract data loading into `load_data` function
- **fce1218** add forecast plotting with fan charts and fix quarterly h-ordering
- **d426306** add .gitignore to exclude MATLAB autosave files
- **efebe3b** add script to run model
- **5af93e6** calc forecasts for all quarterly vars
- **9d56a66 / b27de7d / c600757 / 27b2e9f / 6b476ab** initial scaffolding: functions and
  source code carried over from the earlier `ger-nowcasting` / `sparse-nowcasting` projects

## Project shape (as of 2026-09-08)

- **Goal**: nowcast German fiscal variables (revenues/expenditures) using a
  mixed-frequency (monthly/quarterly) dynamic factor model.
- **MATLAB core** (`src/*.m`): dynamic factor model estimation and
  forecasting — `f_DK2002.m` (Durbin-Koopman-style state space/Kalman
  routines), `f_constructdataset.m`, `f_growth_rates.m`,
  `f_cumulate_level.m`, `f_reseasonalize.m`, `f_nominal_gdp.m`,
  `f_startingvalues.m`, `loadpriors.m`, `GibbsSampler.m`,
  `load_raw_data.m` / `load_sa_data.m`, `remove_outliers.m`,
  `drop_variable.m`, `plot_forecasts.m`. Driven by `main.m` at the repo root.
- **Python data pipeline** (`src/*.py`): builds the datasets the MATLAB
  model consumes.
  - `build_bundesbank_dataset.py` — pulls macro/fiscal series from the
    Bundesbank SDMX API.
  - `build_fiscal_dataset.py` / `build_fiscal_sa_levels.py` — build fiscal
    series (levels, seasonal adjustment).
  - `build_small_dataset.py` — builds a small trial monthly dataset from a
    trial spreadsheet, plus a JSON "dictionary" of per-series metadata
    (`data/trial_small_monthly_dictionary.json`): source description,
    decumulate flag (YTD cumulative -> flow), seasonal-adjustment flag,
    transform, and (new) publication delay.
  - Frequency is encoded directly in mnemonics (`_M` monthly, `_Q`
    quarterly).
- **data/**, **output/**, **tools/** — inputs, generated artifacts
  (including `output/bundesbank_series_codes.md`), and helper tooling.

## Conventions / notes worth remembering

- Mnemonics carry frequency suffixes: `_M` (monthly), `_Q` (quarterly).
- The monthly dictionary JSON is the source of truth for how each series
  should be transformed (decumulate, seasonally adjust, transform type) and,
  as of the in-progress change above, its real-time publication delay.
- `.gitignore` excludes MATLAB autosave (`.asv`) files, though a couple of
  pre-existing `.asv` files remain tracked from before that rule was added.
