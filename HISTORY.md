# Project History

Running log of work on this repo, kept for continuity across Claude Code sessions.
Newest entries at the top. Update this file when a session wraps up a
meaningful chunk of work (new commits, a design decision, or an in-progress
state worth flagging for next time).

## In progress (uncommitted, as of 2026-09-08)

- Adding a `publication_delay` field (days after end of reference period
  until release) to `data/trial_small_monthly_dictionary.json` and to the
  `VARIABLES` table in `src/build_small_dataset.py`. Purpose: support
  real-time nowcasting timing (how stale each real-time observation is).
  Delays for REV/EXP monthly series, IFO, GDP deflator, GDP real, and Bund
  yield were given directly; HICP, IP, retail turnover, and auto sales were
  looked up from Destatis/KBA release schedules (sources noted in a comment
  in `build_small_dataset.py`).

## Commit history summary

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
