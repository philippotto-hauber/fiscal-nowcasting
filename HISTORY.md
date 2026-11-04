# Project History

Running log of work on this repo, kept for continuity across Claude Code sessions.
Newest entries at the top. Update this file when a session wraps up a
meaningful chunk of work (new commits, a design decision, or an in-progress
state worth flagging for next time).

## In progress (uncommitted, as of 2026-11-02)

New data delivery (both trial xlsx files replaced; identical column
structure, values refreshed/extended: monthly to Oct 2026, quarterly to
2026Q3). Reran `build_small_dataset.py` + `build_fiscal_sa_levels.py`
(clean; X-13 now also warns about a trading-day spectrum peak, not just the
usual seasonal one) and `main.m` (10,000 MCMC iterations, ~10 min).
- **Ragged edge broke postprocessing**: `GDP_REAL_Q`/`GDP_NOMINAL_Q` now
  run to 2026Q3, but `GDP_DEFLATOR_Q` and the GG fiscal series stop at
  2026Q2. Fixes:
  - `f_nominal_gdp.m`: real-GDP and deflator forecast windows no longer have
    to coincide; uses their union and pads with actuals (`f_pad_with_actuals`)
    -- previously would have errored.
  - `f_postprocess_draws.m`: EUR anchor now taken at the latest quarter
    where nominal GDP, real GDP AND deflator are all observed (2026Q2 here),
    instead of each series' own last value (which would have mixed Q3
    nominal with a Q2 deflator).
  - `write_forecast_summary.m`: table rows are the union of GDP and balance
    forecast quarters; GDP shows "x.x (actual)" where already published
    (2026Q3), so the Q3 balance forecast is no longer dropped.
- **New plot `src/plot_rev_exp.m`** -> `output/fcasts_rev_exp.png`, called
  from `main.m` after `plot_gdp_deficit`: GG revenues and expenditures as %
  of nominal GDP, history (SA level / raw GDP_NOMINAL_Q) + forecast fan
  (per-draw level / `postproc.ngdp.levels_nom_eur`), same definition as the
  balance ratio, so rev - exp = balance tile. User first got EUR bn levels,
  then asked for % of GDP instead.
- `f_postprocess_draws.m` now also returns `balance_to_gdp.rev_pct`/
  `.exp_pct` (per-draw components of `ratio_pct`); `write_forecast_summary.m`
  adds GG revenues / expenditures (% of GDP) columns from them. Forecast
  quarters only -- history not exported (offered as a follow-up).
- Possible refinement, not done: with nominal + real GDP both observed for
  2026Q3, the Q3 deflator is implicitly known too; currently the model's
  deflator forecast is used for that quarter instead.

## In progress (uncommitted, as of 2026-09-15, continued)

Follow-up in the same session, after the file-split work below: two related
`main.m`/plotting changes, requested together.
- **Dropped `GDP_NOMINAL_Q` from the estimated dataset.** It was one of the
  5 quarterly variables fed into `GibbsSampler.m`, but contributed nothing
  beyond the nominal-GDP anchor -- `GDP_REAL_Q`/`GDP_DEFLATOR_Q` already
  carry the real-GDP/price-level information, and `f_nominal_gdp.m`
  reconstructs an implied nominal GDP index from those two. `main.m` now
  loads it, extracts the full raw history (`ngdp_raw_eur`), then drops its
  row from `dataQ_raw`/`dataQ_sa`/`namesQ` before `f_growth_rates.m` --
  `options.Nq` (and everything downstream that sizes off it, e.g.
  `GibbsSampler.m`'s state-space dimensions) automatically becomes 4.
  Checked `GibbsSampler.m` for anything hardcoded to `Nq == 5`: the only
  literal 5s in there are the temporal-aggregation weight vector
  `[1/3 2/3 3/3 2/3 1/3]` (5 lags per quarterly variable, unrelated to how
  many quarterly variables there are) -- safe.
- **Nominal GDP anchor is no longer hardcoded** (the 2026-09-08 entry's
  `1171696e6` is long gone) **and is no longer a main.m-level scalar** --
  `f_postprocess_draws.m` now takes the full `ngdp_raw_eur` row (not a
  pre-extracted scalar) and derives the anchor internally as its last
  non-NaN value, so it doubles as the source for the new historical ratio
  below.
- **Added a historical general-government balance-to-GDP series.** Now
  that `GDP_NOMINAL_Q` history is loaded (previously only a single anchor
  value was extracted), `f_postprocess_draws.m` also computes
  `balance_to_gdp.hist_dates_dt`/`.hist_ratio_pct` = 100 x (SA
  `REV_GG_TOTAL_Q` - SA `EXP_GG_TOTAL_Q`) / raw `GDP_NOMINAL_Q`, actuals
  only, no MCMC draws -- same definition as the forecast ratio.
  `plot_gdp_deficit.m`'s deficit tile now plots history + forecast (via
  `f_plot_fan.m`, same as the GDP growth tile already did) instead of
  forecast-only.
- Ran `main.m` end-to-end via MATLAB R2023a batch mode (10,000 MCMC
  iterations, ~2.5 min -- noticeably faster than the 2026-09-08 session's
  ~7 min, likely just machine-load variance) to confirm it works; no
  errors. Visually checked `output/gdp_deficit.png`: historical balance
  runs roughly 0% to -5% of GDP, a plausible range for the German general
  government, and the forecast fan bridges cleanly from the last
  historical point.

## In progress (uncommitted, as of 2026-09-15)

Source data for the small trial dataset now ships as two separate files
instead of one: `data/Fiscal_Macro_Dataset_trial_small.xlsx` (monthly
series only) and the new `data/Fiscal_Macro_Dataset_trial_small_quarterly.xlsx`
(quarterly series, one row per quarter, dated at the quarter's first month
-- Jan/Apr/Jul/Oct). Updated `src/build_small_dataset.py` to read the 5
quarterly mnemonics (`EXP_GG_TOTAL_Q`, `REV_GG_TOTAL_Q`, `GDP_DEFLATOR_Q`,
`GDP_REAL_Q`, `GDP_NOMINAL_Q`) from the new file and everything else from
the monthly file, as before. Replaced the old `dequarter()` (which zeroed
out 2-of-3 months of a monthly-repeated quarterly source) with
`requarter()`, which just shifts the new file's quarter-start dates onto
the quarter-end month convention (`+2 months`) used everywhere else in this
dataset; the other two months are simply absent from the sparse source and
become NaN once merged onto the monthly grid, same net effect as before.
- **Real discrepancy found, not just a format change**: for the 3
  EUR-denominated quarterly series (`EXP_GG_TOTAL_Q`, `REV_GG_TOTAL_Q`,
  `GDP_NOMINAL_Q`), the old combined monthly file held the quarterly total
  *divided by 3* and repeated across the quarter's 3 months -- an implied
  monthly-rate convention that only applied to EUR-level series, not the
  index-type ones (`GDP_REAL_Q`, `GDP_DEFLATOR_Q`, unaffected either way).
  The new quarterly file gives the true, undivided quarterly total -- values
  for these 3 mnemonics are now exactly 3x what they were in the previously
  committed `trial_small_monthly.csv`/`fiscal_sa_levels.csv`. User confirmed:
  keep the new file's true totals (no `/3`), since the old convention looked
  like a bug.
- **Checked whether this 3x break's `main.m`'s fiscal-balance-to-GDP calc --
  it doesn't**: `options.anchor_ngdp_eur` (main.m:28-29) is derived at
  runtime from the latest raw `GDP_NOMINAL_Q` level, not hardcoded, so it
  scales by the same 3x as `EXP_GG_TOTAL_Q`/`REV_GG_TOTAL_Q` in
  `f_postprocess_draws.m`'s `balance_to_gdp.ratio_pct` -- numerator and
  denominator both triple, ratio is unchanged. No MATLAB changes needed.
- Reran the full two-step pipeline (`build_small_dataset.py` then
  `build_fiscal_sa_levels.py`) so the dictionary's `seasonally_adjust`/
  `transform` fields (added by the second step) stay populated -- the first
  step alone overwrites the dictionary file and would silently drop them.
  Both ran clean (same routine X-13 spectrum-peak warning as always).
- New quarterly file also carries one series with no mnemonic yet:
  "Gross Domestic Product, Total, Current Prices, EUR" (unadjusted/NSA
  nominal GDP, distinct from the existing SA `GDP_NOMINAL_Q`). Not added --
  out of scope for this file-split adaptation; flag if it becomes useful.

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
