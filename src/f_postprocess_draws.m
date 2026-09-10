function postproc = f_postprocess_draws(draws, dataQ, namesQ, dates, anchor_ngdp_eur)

% Post-processes MCMC forecast draws into two derived quantities, for every
% draw:
%   i)  nominal GDP (reuses f_nominal_gdp.m as-is), rescaled from an implied
%       index onto a EUR level using a caller-supplied anchor.
%   ii) the general government fiscal balance (REV_GG_TOTAL_Q -
%       EXP_GG_TOTAL_Q; positive = surplus) as a percent of that nominal GDP.
%
% Background on the GDP rescaling: f_nominal_gdp.m combines the model's
% forecasts for GDP_REAL_Q and GDP_DEFLATOR_Q -- both index series in this
% dataset, with no EUR-denominated nominal GDP series available -- via
% nominal = real x deflator / 100. That produces an implied nominal GDP
% INDEX, not a EUR amount, so it cannot be used to form a genuine
% balance-to-GDP percentage on its own. This function rescales that index
% onto EUR terms using anchor_ngdp_eur, an externally supplied nominal GDP
% level (EUR) for the last actual (pre-forecast) quarter of GDP_REAL_Q /
% GDP_DEFLATOR_Q -- e.g. looked up from Destatis/Bundesbank for that
% specific quarter. The scale factor is
%   anchor_ngdp_eur / (last actual GDP_REAL_Q level x last actual
%                       GDP_DEFLATOR_Q level / 100)
% applied uniformly to every forecast quarter and draw. This is a levels
% anchor only -- it does not correct for any drift between the index's
% implied growth and actual EUR nominal GDP growth over the forecast
% horizon.
%
% Inputs:
%   draws           : must have fields .forecasts_restand (Hq_max x Nq x
%                      Ndraws, destandardized q/q growth rate (%) forecasts,
%                      as computed in main.m) and .Hq (1 x Nq, per-variable
%                      forecast horizon in quarters) -- both set by
%                      GibbsSampler.m.
%   dataQ           : quarterly levels, variables x time. Seasonally
%                      adjusted (dataQ_sa from load_sa_data()) is what main.m
%                      passes in -- GDP_REAL_Q/GDP_DEFLATOR_Q are unaffected
%                      either way since neither is SA in this pipeline, and
%                      the fiscal balance is computed on SA levels to match.
%   namesQ          : quarterly mnemonics matching dataQ's rows and draws'
%                      columns.
%   dates           : 1 x T, year + (month-1)/12, matching dataQ's time axis
%                      (e.g. load_raw_data()'s dates_full, per main.m).
%   anchor_ngdp_eur : scalar, nominal GDP for the last actual quarter of
%                      GDP_REAL_Q / GDP_DEFLATOR_Q in dataQ, in the SAME
%                      units as EXP_GG_TOTAL_Q/REV_GG_TOTAL_Q in dataQ --
%                      raw EUR in this dataset, NOT EUR millions (a mismatch
%                      here silently produces a balance-to-GDP ratio too
%                      large by a factor of 1e6). Supplied by the caller
%                      (main.m); not derivable from this dataset.
%
% Returns postproc, a struct with:
%   .ngdp             : output of f_nominal_gdp.m (dates, levels_real,
%                        levels_defl, levels_nom [index]), plus
%                        .levels_nom_eur (Hq x Ndraws, rescaled to EUR).
%   .balance          : .dates, .levels_rev, .levels_exp, .levels_balance
%                        (all Hq_i x Ndraws SA level forecasts; levels_balance
%                        = levels_rev - levels_exp, positive = surplus).
%   .balance_to_gdp   : .dates (quarters common to .balance and .ngdp) and
%                        .ratio_pct (Hq_common x Ndraws, balance / nominal
%                        GDP (EUR) x 100).

REV_VAR = 'REV_GG_TOTAL_Q';
EXP_VAR = 'EXP_GG_TOTAL_Q';

yr_all = floor(dates);
mo_all = round((dates - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

% --- i) nominal GDP, rescaled from index to EUR ---------------------------

ngdp = f_nominal_gdp(draws, dataQ, namesQ, dates);

anchor_real = f_last_actual(dataQ, namesQ, 'GDP_REAL_Q');
anchor_defl = f_last_actual(dataQ, namesQ, 'GDP_DEFLATOR_Q');
anchor_ngdp_index = anchor_real * anchor_defl / 100;

scale = anchor_ngdp_eur / anchor_ngdp_index;
ngdp.levels_nom_eur = ngdp.levels_nom * scale;

% --- ii) general government fiscal balance, SA levels ----------------------

[dates_rev, levels_rev] = f_cumulate_level(draws, dataQ, namesQ, dates_dt, REV_VAR);
[dates_exp, levels_exp] = f_cumulate_level(draws, dataQ, namesQ, dates_dt, EXP_VAR);

if numel(dates_rev) ~= numel(dates_exp) || any(dates_rev ~= dates_exp)
    error('f_postprocess_draws: %s and %s do not share the same forecast horizon.', REV_VAR, EXP_VAR);
end

balance.dates = dates_rev;
balance.levels_rev = levels_rev;
balance.levels_exp = levels_exp;
balance.levels_balance = levels_rev - levels_exp;

% --- balance as a percent of nominal GDP, over their common quarters ------

[common_dates, i_bal, i_gdp] = intersect(balance.dates, ngdp.dates);
if isempty(common_dates)
    error('f_postprocess_draws: balance and nominal GDP forecasts share no common quarter.');
end

balance_to_gdp.dates = common_dates;
balance_to_gdp.ratio_pct = 100 * balance.levels_balance(i_bal, :) ./ ngdp.levels_nom_eur(i_gdp, :);

postproc.ngdp = ngdp;
postproc.balance = balance;
postproc.balance_to_gdp = balance_to_gdp;

end


function level = f_last_actual(dataQ, namesQ, mnemonic)
i = find(strcmp(namesQ, mnemonic));
if isempty(i)
    error('f_postprocess_draws: %s not found among quarterly variables.', mnemonic);
end
idx_obs = find(~isnan(dataQ(i, :)));
level = dataQ(i, idx_obs(end));
end
