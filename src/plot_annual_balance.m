function plot_annual_balance(postproc, dataQ_sa, namesQ, ngdp_raw_eur, dates_full, outpath)

% Plots the predictive density of the general government balance as a
% percent of nominal GDP, for the most recent calendar year that mixes
% actual and forecast quarters: 100 * sum_q(REV_GG_TOTAL_Q -
% EXP_GG_TOTAL_Q) / sum_q(GDP_NOMINAL_Q), summed over that year's 4
% quarters (SA levels for REV/EXP; GDP_NOMINAL_Q is already SA at the
% source -- see main.m).
%
% Generic across vintages: walks calendar years back from the latest one
% that could possibly be complete, and picks the first (i.e. most recent)
% year where every one of its 4 quarters is covered -- either by an actual
% observation, or by a forecast quarter (one of postproc.balance_to_gdp.dates
% -- exactly where both a REV/EXP forecast draw and a nominal-GDP forecast
% draw exist for the same MCMC draw) -- AND at least one quarter is a
% forecast (a fully-actual year has no predictive density to plot). This
% does NOT assume any fixed split of actual vs. forecast quarters (e.g. "2
% actual + 2 forecast") -- it works whether the current year has 1, 2, or 3
% forecast quarters left. A year's actual quarters (if any) contribute a
% constant; its forecast quarters contribute per-draw levels, summed
% before the ratio is taken (summing per-quarter ratios directly would be
% wrong). If no such year exists (e.g. the vintage's last actual quarter is
% already a Q4, so the most recent complete year is fully actual), nothing
% is plotted.
%
% Inputs:
%   postproc     : output of f_postprocess_draws.m; uses .balance
%                   (.dates, .levels_balance), .ngdp (.dates,
%                   .levels_nom_eur), and .balance_to_gdp.dates.
%   dataQ_sa     : quarterly SA levels, variables x time (post
%                   GDP_NOMINAL_Q-drop, as built in main.m).
%   namesQ       : quarterly mnemonics matching dataQ_sa's rows.
%   ngdp_raw_eur : 1 x T, raw (source-SA) nominal GDP level
%                   (GDP_NOMINAL_Q), EUR, matching dataQ_sa's time axis
%                   (see main.m).
%   dates_full   : 1 x T, year + (month-1)/12, matching dataQ_sa's time
%                   axis.
%   outpath      : directory to save 'annual_balance.png' into, or ''/
%                   omitted to skip saving.

if nargin < 6 || isempty(outpath)
    outpath = '';
end

REV_VAR = 'REV_GG_TOTAL_Q';
EXP_VAR = 'EXP_GG_TOTAL_Q';

i_rev = find(strcmp(namesQ, REV_VAR));
i_exp = find(strcmp(namesQ, EXP_VAR));

yr_all   = floor(dates_full);
mo_all   = round((dates_full - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

rev_actual = dataQ_sa(i_rev, :);
exp_actual = dataQ_sa(i_exp, :);
gdp_actual = ngdp_raw_eur;

% Forecast quarters usable here are exactly those with BOTH a balance and
% a nominal-GDP forecast draw for the same MCMC draw (postproc.balance and
% postproc.ngdp can otherwise have different horizons -- REV/EXP_GG_TOTAL_Q
% and GDP_REAL_Q/GDP_DEFLATOR_Q have different real-time publication
% delays, so different Hq).
fc_dates = postproc.balance_to_gdp.dates;
[~, i_bal_fc] = ismember(fc_dates, postproc.balance.dates);
[~, i_gdp_fc] = ismember(fc_dates, postproc.ngdp.dates);
fc_balance = postproc.balance.levels_balance(i_bal_fc, :);  % Hfc x Ndraws
fc_gdp     = postproc.ngdp.levels_nom_eur(i_gdp_fc, :);     % Hfc x Ndraws
Ndraws     = size(fc_balance, 2);

last_actual_yr = max([year(dates_dt(find(~isnan(rev_actual), 1, 'last'))), ...
                       year(dates_dt(find(~isnan(exp_actual), 1, 'last'))), ...
                       year(dates_dt(find(~isnan(gdp_actual), 1, 'last')))]);
if isempty(fc_dates)
    yr_end = last_actual_yr;
else
    yr_end = max(last_actual_yr, max(year(fc_dates)));
end
yr_start = min([year(dates_dt(find(~isnan(rev_actual), 1))), ...
                year(dates_dt(find(~isnan(exp_actual), 1))), ...
                year(dates_dt(find(~isnan(gdp_actual), 1)))]);

target_year  = [];
target_draws = [];

for y = yr_end : -1 : yr_start
    q_dates = datetime(y, [3 6 9 12], 1);

    const_balance = 0;
    const_gdp     = 0;
    draw_balance  = zeros(1, Ndraws);
    draw_gdp      = zeros(1, Ndraws);
    has_draw      = false;
    complete      = true;

    for q = 1 : 4
        idx_actual = find(dates_dt == q_dates(q));
        idx_fc     = find(fc_dates == q_dates(q));
        if ~isempty(idx_actual) && ~isnan(rev_actual(idx_actual)) && ...
                ~isnan(exp_actual(idx_actual)) && ~isnan(gdp_actual(idx_actual))
            const_balance = const_balance + (rev_actual(idx_actual) - exp_actual(idx_actual));
            const_gdp     = const_gdp + gdp_actual(idx_actual);
        elseif ~isempty(idx_fc)
            draw_balance = draw_balance + fc_balance(idx_fc, :);
            draw_gdp     = draw_gdp + fc_gdp(idx_fc, :);
            has_draw = true;
        else
            complete = false;
            break;
        end
    end

    if complete && has_draw
        target_year  = y;
        target_draws = 100 * (const_balance + draw_balance) ./ (const_gdp + draw_gdp);
        break;
    end
end

if isempty(target_year)
    warning('plot_annual_balance: no calendar year mixes actual and forecast quarters; nothing to plot.');
    return;
end

% --- plot: predictive density for target_year ------------------------------

blue_dark  = [0.13 0.47 0.71];
blue_mid   = [0.53 0.75 0.90];
blue_light = [0.78 0.89 0.95];

pct = prctile(target_draws, [2.5 25 50 75 97.5]);
[f, xi] = ksdensity(target_draws);

% Match the fan charts elsewhere in this pipeline: shade/draw only the 95%
% interval, nothing in the tails beyond it.
idx95 = xi >= pct(1) & xi <= pct(5);
xi95  = xi(idx95);
f95   = f(idx95);
idx50 = xi95 >= pct(2) & xi95 <= pct(4);

figure;
hold on;
h95 = fill([xi95, fliplr(xi95)], [f95, zeros(size(f95))], blue_light, 'EdgeColor', 'none');
h50 = fill([xi95(idx50), fliplr(xi95(idx50))], [f95(idx50), zeros(1, nnz(idx50))], blue_mid, 'EdgeColor', 'none');
plot(xi95, f95, 'Color', blue_dark, 'LineWidth', 1.5);
hmed = xline(pct(3), '-', 'Color', blue_dark, 'LineWidth', 2);
hold off;

xlabel('% of GDP');
ylabel('Density');
title(sprintf('General government balance, %% of nominal GDP -- predictive density, %d', target_year), 'Interpreter', 'none');
legend([hmed, h50, h95], {'Median', '50% interval', '95% interval'}, 'Location', 'best');
grid on;

if ~isempty(outpath)
    exportgraphics(gcf, fullfile(outpath, 'annual_balance.png'));
end

end
