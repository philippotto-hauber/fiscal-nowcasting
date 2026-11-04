function plot_gdp_deficit(draws, postproc, dataQ_restand, dates, namesQ, outpath, hist_start_year)

% Plots two fan charts (as tiles in one figure), both history + forecast:
% real GDP q/q growth and the general government fiscal balance as a
% percent of nominal GDP (see f_postprocess_draws.m for how the historical
% and forecast ratios are derived).
%
% Inputs:
%   draws            : must have fields .forecasts_restand (Hq_max x Nq x
%                       Ndraws, destandardized q/q growth rate (%)
%                       forecasts) and .Hq (1 x Nq, per-variable forecast
%                       horizon in quarters) -- both set by GibbsSampler.m.
%   postproc         : output of f_postprocess_draws.m; only .balance_to_gdp
%                       (.dates, .ratio_pct, .hist_dates_dt,
%                       .hist_ratio_pct) is used here.
%   dataQ_restand    : destandardized quarterly SA q/q growth rates,
%                       variables x time (dataQ_stand .* stdsQ' + meansQ',
%                       as computed in main.m).
%   dates            : 1 x T, year + (month-1)/12, matching
%                       dataQ_restand's time axis.
%   namesQ           : quarterly mnemonics matching dataQ_restand's rows
%                       and draws' columns.
%   outpath          : directory to save 'fcasts_gdp_deficit.png' into, or
%                       ''/omitted to skip saving.
%   hist_start_year  : earliest year (as year + (month-1)/12) of GDP growth
%                       history to plot, or omitted/[] for all history.

if nargin < 6 || isempty(outpath)
    outpath = '';
end
if nargin < 7 || isempty(hist_start_year)
    hist_start_year = -Inf;
end

GDP_VAR = 'GDP_REAL_Q';

i = find(strcmp(namesQ, GDP_VAR));
if isempty(i)
    error('plot_gdp_deficit: %s not found among quarterly variables.', GDP_VAR);
end

Hq_max = size(draws.forecasts_restand, 1);

yr_all   = floor(dates);
mo_all   = round((dates - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);
snap_qend = @(dt) datetime(year(dt), ceil(month(dt) / 3) * 3, 1);

pctiles = prctile(draws.forecasts_restand, [2.5 25 50 75 97.5], 3);

figure;
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

% --- tile 1: real GDP q/q growth, history + forecast -----------------------
nexttile;
idx_Q_i  = find(~isnan(dataQ_restand(i, :)));
idx_plot = idx_Q_i(dates(idx_Q_i) >= hist_start_year);
hist_dates_dt = snap_qend(dates_dt(idx_plot) - calmonths(1));
hist_vals     = dataQ_restand(i, idx_plot);

Hq_i    = draws.Hq(i);
j_start = Hq_max - Hq_i + 1;
last_hist_dt     = snap_qend(dates_dt(idx_Q_i(end)) - calmonths(1));
forecast_dates   = last_hist_dt + calmonths(3 * (1 : Hq_i));
forecast_pctiles = reshape(pctiles(j_start:Hq_max, i, :), Hq_i, 5);

[hhist, hmed, h50, h95] = f_plot_fan(hist_dates_dt, hist_vals, forecast_dates, forecast_pctiles);
title('Real GDP', 'Interpreter', 'none');
ylabel('q/q (%)');
leg_handles = [hhist, hmed, h50, h95];

% --- tile 2: GG fiscal balance, % of nominal GDP, history + forecast ------
nexttile;
hist_dates_bal = postproc.balance_to_gdp.hist_dates_dt;
hist_vals_bal  = postproc.balance_to_gdp.hist_ratio_pct;
hist_years_bal = year(hist_dates_bal) + (month(hist_dates_bal) - 1) / 12;
idx_hist_bal   = find(~isnan(hist_vals_bal) & hist_years_bal >= hist_start_year);

balance_pctiles = prctile(postproc.balance_to_gdp.ratio_pct, [2.5 25 50 75 97.5], 2);
f_plot_fan(hist_dates_bal(idx_hist_bal), hist_vals_bal(idx_hist_bal), ...
           postproc.balance_to_gdp.dates, balance_pctiles);
title('General government balance, % of nominal GDP', 'Interpreter', 'none');
ylabel('% of GDP');

lgd = legend(leg_handles, ...
             'Historical', 'Median forecast', '50% interval', '95% interval', ...
             'Orientation', 'horizontal');
lgd.Layout.Tile = 'south';

if ~isempty(outpath)
    exportgraphics(gcf, fullfile(outpath, 'fcasts_gdp_deficit.png'));
end
end
