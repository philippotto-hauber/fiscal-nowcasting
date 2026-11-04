function postproc = f_postprocess_draws(draws, dataQ, namesQ, dates, ngdp_raw_eur)

% Post-processes MCMC forecast draws into two derived quantities, for every
% draw:
%   i)  nominal GDP (reuses f_nominal_gdp.m as-is), rescaled from an implied
%       index onto a EUR level using an anchor read off ngdp_raw_eur.
%   ii) the general government fiscal balance (REV_GG_TOTAL_Q -
%       EXP_GG_TOTAL_Q; positive = surplus) as a percent of that nominal
%       GDP, both as a forecast (from the MCMC draws) and, using the same
%       definition, as actual history (no draws involved).
%
% Background on the GDP rescaling: f_nominal_gdp.m combines the model's
% forecasts for GDP_REAL_Q and GDP_DEFLATOR_Q -- both index series in this
% dataset, with no EUR-denominated nominal GDP series among the *estimated*
% variables -- via nominal = real x deflator / 100. That produces an
% implied nominal GDP INDEX, not a EUR amount, so it cannot be used to form
% a genuine balance-to-GDP percentage on its own. This function rescales
% that index onto EUR terms using an anchor: an actual level from
% ngdp_raw_eur (GDP_NOMINAL_Q, raw EUR -- see main.m; kept out of the
% estimated dataset itself, but still loaded for this purpose). The scale
% factor is (all three taken at the latest quarter where all three are
% observed -- the series can have a ragged edge):
%   anchor_ngdp_eur / (GDP_REAL_Q level x
%                       GDP_DEFLATOR_Q level / 100)
% applied uniformly to every forecast quarter and draw. This is a levels
% anchor only -- it does not correct for any drift between the index's
% implied growth and actual EUR nominal GDP growth over the forecast
% horizon.
%
% Inputs:
%   draws        : must have fields .forecasts_restand (Hq_max x Nq x
%                   Ndraws, destandardized q/q growth rate (%) forecasts,
%                   as computed in main.m) and .Hq (1 x Nq, per-variable
%                   forecast horizon in quarters) -- both set by
%                   GibbsSampler.m.
%   dataQ        : quarterly levels, variables x time. Seasonally adjusted
%                   (dataQ_sa from load_sa_data()) is what main.m passes in
%                   -- GDP_REAL_Q/GDP_DEFLATOR_Q are unaffected either way
%                   since neither is SA in this pipeline, and the fiscal
%                   balance (both forecast and historical) is computed on
%                   SA levels to match.
%   namesQ       : quarterly mnemonics matching dataQ's rows and draws'
%                   columns. Must NOT include GDP_NOMINAL_Q (dropped from
%                   the estimated dataset in main.m); ngdp_raw_eur supplies
%                   nominal GDP separately, below.
%   dates        : 1 x T, year + (month-1)/12, matching dataQ's time axis
%                   (e.g. load_raw_data()'s dates_full, per main.m).
%   ngdp_raw_eur : 1 x T, raw (source-SA) nominal GDP level (GDP_NOMINAL_Q),
%                   EUR, NOT EUR millions (a mismatch here silently produces
%                   a balance-to-GDP ratio too large by a factor of 1e6),
%                   matching dataQ's time axis. The anchor used for i) is
%                   its value at the latest quarter also observed for real GDP and the deflator; the full row is also
%                   used for the historical balance-to-GDP ratio in ii).
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
%                        GDP (EUR) x 100) -- forecast only, one column per
%                        draw; .rev_pct/.exp_pct (same shape, revenues/
%                        expenditures as % of the same nominal GDP draw);
%                        plus .hist_dates_dt/.hist_ratio_pct (1 x T
%                        each, NaN outside actual quarters), the same ratio
%                        computed from history, no draws involved.

REV_VAR = 'REV_GG_TOTAL_Q';
EXP_VAR = 'EXP_GG_TOTAL_Q';

yr_all = floor(dates);
mo_all = round((dates - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);


% --- i) nominal GDP, rescaled from index to EUR ---------------------------

ngdp = f_nominal_gdp(draws, dataQ, namesQ, dates);

% Anchor all three series at the SAME quarter: the latest one where nominal
% GDP (EUR), real GDP and the deflator are all observed. With a ragged edge
% (e.g. real/nominal GDP already out for a quarter whose deflator isn't),
% each series' own last value would refer to different quarters.
i_real = f_row(namesQ, 'GDP_REAL_Q');
i_defl = f_row(namesQ, 'GDP_DEFLATOR_Q');
idx_anchor = find(~isnan(ngdp_raw_eur) & ~isnan(dataQ(i_real, :)) & ~isnan(dataQ(i_defl, :)), 1, 'last');
if isempty(idx_anchor)
    error('f_postprocess_draws: no quarter with nominal GDP, real GDP and deflator all observed.');
end
anchor_ngdp_eur   = ngdp_raw_eur(idx_anchor);
anchor_ngdp_index = dataQ(i_real, idx_anchor) * dataQ(i_defl, idx_anchor) / 100;

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
% Components of the same ratio (rev_pct - exp_pct = ratio_pct, per draw).
balance_to_gdp.rev_pct   = 100 * balance.levels_rev(i_bal, :) ./ ngdp.levels_nom_eur(i_gdp, :);
balance_to_gdp.exp_pct   = 100 * balance.levels_exp(i_bal, :) ./ ngdp.levels_nom_eur(i_gdp, :);

% --- balance as a percent of nominal GDP, actual history -------------------
% Same definition as the forecast above (SA revenue/expenditure levels over
% raw nominal GDP), computed directly on actuals -- no draws, no cumulation.

i_rev = find(strcmp(namesQ, REV_VAR));
i_exp = find(strcmp(namesQ, EXP_VAR));

balance_to_gdp.hist_dates_dt = dates_dt;
balance_to_gdp.hist_ratio_pct = 100 * (dataQ(i_rev, :) - dataQ(i_exp, :)) ./ ngdp_raw_eur;

postproc.ngdp = ngdp;
postproc.balance = balance;
postproc.balance_to_gdp = balance_to_gdp;

end


function i = f_row(namesQ, mnemonic)
i = find(strcmp(namesQ, mnemonic));
if isempty(i)
    error('f_postprocess_draws: %s not found among quarterly variables.', mnemonic);
end
end
