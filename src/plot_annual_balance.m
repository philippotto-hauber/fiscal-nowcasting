function plot_annual_balance(postproc, dataQ_sa, namesQ, ngdp_raw_eur, dates_full, outpath)

% Plots predictive densities for the current calendar year and the next
% one, as a 2x2 panel: column 1 real GDP annual growth, column 2 the
% general government balance as a percent of nominal GDP; row 1 the
% current year, row 2 the next one. Each density is drawn in full (the
% whole kernel-density curve, tapering to ~0 in the tails), with only its
% 50%/95% central intervals shaded; each column shares one x-axis range
% (the union of its two years' full curves) so the two densities in a
% column are visually comparable.
%   - GDP growth, year Y: 100 * (sum_q(GDP_REAL_Q, year Y) /
%     sum_q(GDP_REAL_Q, year Y-1) - 1), i.e. the annual level (approximated
%     as the sum of the year's 4 quarterly index levels, consistent with
%     how the balance ratio below sums quarterly flows/levels) against the
%     same sum for the prior year.
%   - Balance, year Y: 100 * sum_q(REV_GG_TOTAL_Q - EXP_GG_TOTAL_Q) /
%     sum_q(GDP_NOMINAL_Q), summed over year Y's 4 quarters (SA levels for
%     REV/EXP; GDP_NOMINAL_Q is already SA at the source -- see main.m).
%
% Both series are built on the same "sum a year's 4 quarters, mixing
% actual (constant) and forecast (per-draw) as needed" building block
% (f_annual_level, below) -- generic across vintages: a year's actual
% quarters (if any) contribute a constant; its forecast quarters (one of
% the relevant forecast-dates list -- REV/EXP_GG_TOTAL_Q, GDP_NOMINAL_Q
% (via postproc.ngdp), and GDP_REAL_Q (also via postproc.ngdp) can each
% have different real-time publication delays, hence different per-variable
% forecast horizons) contribute per-draw levels, summed before any ratio is
% taken (summing per-quarter ratios/growth rates directly would be wrong).
%
% "Current year" is found by walking calendar years back from the latest
% one that could possibly be complete, picking the first (most recent)
% year where every one of its 4 quarters is covered by the fiscal
% series (REV/EXP/GDP_NOMINAL) -- either actual or forecast -- AND the
% year has BOTH at least one actual and at least one forecast quarter (a
% fully-actual year has no predictive density to plot; a fully-forecast
% year, now reachable since main.m's horizon runs into the year after
% next, is "next year", not "current" -- requiring both kinds of quarter
% is what tells them apart). "Next year" is current + 1, which (since
% main.m's forecast horizon always runs through December of the year
% after the vintage's year) should itself be a fully-forecast, complete
% year for the fiscal series. GDP growth reuses the same curr_year/
% next_year calendar labels, but re-checks completeness against
% GDP_REAL_Q's own actual/forecast coverage (including curr_year - 1, the
% growth base year, expected to be fully actual) since its publication
% delay/horizon need not exactly match the fiscal series'. Any panel whose
% required year(s) aren't complete for that series is skipped (with a
% warning) rather than erroring, so this degrades gracefully instead of
% assuming a fixed layout.
%
% Inputs:
%   postproc     : output of f_postprocess_draws.m; uses .balance
%                   (.dates, .levels_balance), .ngdp (.dates,
%                   .levels_nom_eur, .levels_real), and
%                   .balance_to_gdp.dates.
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

REV_VAR  = 'REV_GG_TOTAL_Q';
EXP_VAR  = 'EXP_GG_TOTAL_Q';
REAL_VAR = 'GDP_REAL_Q';

i_rev  = find(strcmp(namesQ, REV_VAR));
i_exp  = find(strcmp(namesQ, EXP_VAR));
i_real = find(strcmp(namesQ, REAL_VAR));

yr_all   = floor(dates_full);
mo_all   = round((dates_full - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

rev_actual     = dataQ_sa(i_rev, :);
exp_actual     = dataQ_sa(i_exp, :);
gdp_actual     = ngdp_raw_eur;
real_actual    = dataQ_sa(i_real, :);
balance_actual = rev_actual - exp_actual;  % NaN wherever either input is NaN

% Forecast quarters usable for the balance ratio are exactly those with
% BOTH a balance and a nominal-GDP forecast draw for the same MCMC draw
% (postproc.balance and postproc.ngdp can otherwise have different
% horizons). GDP growth instead uses postproc.ngdp's own dates/levels_real
% directly -- no such intersection needed since it only involves one
% series.
bal_fc_dates = postproc.balance_to_gdp.dates;
[~, i_bal_fc] = ismember(bal_fc_dates, postproc.balance.dates);
[~, i_gdp_fc] = ismember(bal_fc_dates, postproc.ngdp.dates);
fc_balance = postproc.balance.levels_balance(i_bal_fc, :);  % Hfc x Ndraws
fc_gdp     = postproc.ngdp.levels_nom_eur(i_gdp_fc, :);     % Hfc x Ndraws

real_fc_dates = postproc.ngdp.dates;
fc_real       = postproc.ngdp.levels_real;                 % Hq x Ndraws

% --- find curr_year / next_year off the fiscal series -----------------------

last_actual_yr = max([year(dates_dt(find(~isnan(rev_actual), 1, 'last'))), ...
                       year(dates_dt(find(~isnan(exp_actual), 1, 'last'))), ...
                       year(dates_dt(find(~isnan(gdp_actual), 1, 'last')))]);
if isempty(bal_fc_dates)
    yr_end = last_actual_yr;
else
    yr_end = max(last_actual_yr, max(year(bal_fc_dates)));
end
yr_start = min([year(dates_dt(find(~isnan(rev_actual), 1))), ...
                year(dates_dt(find(~isnan(exp_actual), 1))), ...
                year(dates_dt(find(~isnan(gdp_actual), 1)))]);

curr_year = [];

for y = yr_end : -1 : yr_start
    [~, bal_complete, bal_has_draw, bal_has_actual] = f_annual_level(y, dates_dt, balance_actual, bal_fc_dates, fc_balance);
    [~, ngdp_complete] = f_annual_level(y, dates_dt, gdp_actual, bal_fc_dates, fc_gdp);
    if bal_complete && ngdp_complete && bal_has_draw && bal_has_actual
        curr_year = y;
        break;
    end
end

if isempty(curr_year)
    warning('plot_annual_balance: no calendar year mixes actual and forecast quarters; nothing to plot.');
    return;
end

next_year = curr_year + 1;

curr_balance_pct    = [];
next_balance_pct    = [];
curr_gdp_growth_pct = [];
next_gdp_growth_pct = [];

% --- balance ratio, curr_year / next_year -----------------------------------

[curr_balance_draws, curr_bal_ok] = f_annual_level(curr_year, dates_dt, balance_actual, bal_fc_dates, fc_balance);
[curr_ngdp, curr_ngdp_ok] = f_annual_level(curr_year, dates_dt, gdp_actual, bal_fc_dates, fc_gdp);
have_bal_curr = curr_bal_ok && curr_ngdp_ok;
if have_bal_curr
    curr_balance_pct = 100 * curr_balance_draws ./ curr_ngdp;
end

[next_balance_draws, next_bal_ok] = f_annual_level(next_year, dates_dt, balance_actual, bal_fc_dates, fc_balance);
[next_ngdp, next_ngdp_ok] = f_annual_level(next_year, dates_dt, gdp_actual, bal_fc_dates, fc_gdp);
have_bal_next = next_bal_ok && next_ngdp_ok;
if have_bal_next
    next_balance_pct = 100 * next_balance_draws ./ next_ngdp;
else
    warning('plot_annual_balance: %d is not a complete forecast year for the fiscal balance; skipping that panel.', next_year);
end

% --- GDP annual growth, curr_year / next_year -------------------------------

prev_year = curr_year - 1;
[real_prev, prev_ok]     = f_annual_level(prev_year, dates_dt, real_actual, real_fc_dates, fc_real);
[real_curr, real_curr_ok] = f_annual_level(curr_year, dates_dt, real_actual, real_fc_dates, fc_real);
[real_next, real_next_ok] = f_annual_level(next_year, dates_dt, real_actual, real_fc_dates, fc_real);

have_gdp_curr = prev_ok && real_curr_ok;
have_gdp_next = real_curr_ok && real_next_ok;

if have_gdp_curr
    curr_gdp_growth_pct = 100 * (real_curr ./ real_prev - 1);
else
    warning('plot_annual_balance: %d is not a complete year for real GDP growth; skipping that panel.', curr_year);
end
if have_gdp_next
    next_gdp_growth_pct = 100 * (real_next ./ real_curr - 1);
else
    warning('plot_annual_balance: %d is not a complete forecast year for real GDP growth; skipping that panel.', next_year);
end

% --- plot: 2x2 predictive densities -----------------------------------------
% Layout: column 1 = GDP growth, column 2 = fiscal balance; row 1 =
% curr_year, row 2 = next_year. Each column shares one x-axis range (the
% union of its two years' 95% intervals) so the two densities in a column
% are visually comparable.

gdp_xrange = f_column_xrange(curr_gdp_growth_pct, next_gdp_growth_pct);
bal_xrange = f_column_xrange(curr_balance_pct, next_balance_pct);

figure;
tiledlayout(2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
leg_handles = [];

nexttile;
if have_gdp_curr
    [hmed, h50, h95] = f_plot_density_tile(curr_gdp_growth_pct, sprintf('GDP: %d', curr_year), '% y/y', gdp_xrange);
    leg_handles = [hmed, h50, h95];
else
    axis off;
end

nexttile;
if have_bal_curr
    [hmed, h50, h95] = f_plot_density_tile(curr_balance_pct, sprintf('Fiscal balance: %d', curr_year), '% of GDP', bal_xrange);
    if isempty(leg_handles)
        leg_handles = [hmed, h50, h95];
    end
else
    axis off;
end

nexttile;
if have_gdp_next
    f_plot_density_tile(next_gdp_growth_pct, sprintf('GDP: %d', next_year), '% y/y', gdp_xrange);
else
    axis off;
end

nexttile;
if have_bal_next
    f_plot_density_tile(next_balance_pct, sprintf('Fiscal balance: %d', next_year), '% of GDP', bal_xrange);
else
    axis off;
end

if ~isempty(leg_handles)
    lgd = legend(leg_handles, {'Median', '50% interval', '95% interval'}, 'Orientation', 'horizontal');
    lgd.Layout.Tile = 'south';
end
sgtitle('Predictive densities', 'Interpreter', 'none');

if ~isempty(outpath)
    exportgraphics(gcf, fullfile(outpath, 'annual_balance.png'));
end

end


function [level, complete, has_draw, has_actual] = f_annual_level(y, dates_dt, actual_row, fc_dates, fc_levels)

% Sums one quarterly series' 4 quarters for calendar year y, mixing actual
% (constant) and forecast (per-draw) quarters as needed -- see the
% file-level comment above for the definition. Returns complete = false if
% any of the year's 4 quarters is covered by neither an actual observation
% nor a forecast draw; has_draw/has_actual = false if none of the year's
% quarters is, respectively, a forecast draw / an actual observation.
%
%   level : 1 x Ndraws (a fully-actual year still returns Ndraws identical
%           copies of the same constant, for uniform downstream arithmetic
%           against a partly- or fully-forecast year), or [] if incomplete.

Ndraws = size(fc_levels, 2);
q_dates = datetime(y, [3 6 9 12], 1);

const     = 0;
draw_sum  = zeros(1, Ndraws);
has_draw  = false;
has_actual = false;
complete  = true;

for q = 1 : 4
    idx_actual = find(dates_dt == q_dates(q));
    idx_fc     = find(fc_dates == q_dates(q));
    if ~isempty(idx_actual) && ~isnan(actual_row(idx_actual))
        const = const + actual_row(idx_actual);
        has_actual = true;
    elseif ~isempty(idx_fc)
        draw_sum = draw_sum + fc_levels(idx_fc, :);
        has_draw = true;
    else
        complete = false;
        break;
    end
end

if complete
    level = const + draw_sum;
else
    level = [];
end

end


function xrange = f_column_xrange(a, b)

% Union of two (possibly empty) draw vectors' full kernel-density support,
% for sharing one x-axis range across a column's two year-panels (matches
% what f_plot_density_tile actually draws -- the whole curve, not just its
% 95% band). Returns [] if both are empty (nothing plotted in that column,
% so no shared range needed).

bounds = [];
if ~isempty(a)
    [~, xi] = ksdensity(a);
    bounds = [bounds, xi(1), xi(end)];
end
if ~isempty(b)
    [~, xi] = ksdensity(b);
    bounds = [bounds, xi(1), xi(end)];
end
if isempty(bounds)
    xrange = [];
else
    xrange = [min(bounds), max(bounds)];
end

end


function [hmed, h50, h95] = f_plot_density_tile(target_draws, tile_title, xlab, xrange)

blue_dark  = [0.13 0.47 0.71];
blue_mid   = [0.53 0.75 0.90];
blue_light = [0.78 0.89 0.95];

pct = prctile(target_draws, [2.5 25 50 75 97.5]);
[f, xi] = ksdensity(target_draws);

% Draw the full curve (tapering to ~0 in the tails); only the 50%/95%
% central intervals are shaded, matching the highlighted-interval
% convention used elsewhere in this pipeline. Draws beyond the 95% band
% still exist -- they're just not shaded, not cut off.
idx95 = xi >= pct(1) & xi <= pct(5);
idx50 = xi >= pct(2) & xi <= pct(4);

hold on;
h95 = fill([xi(idx95), fliplr(xi(idx95))], [f(idx95), zeros(1, nnz(idx95))], blue_light, 'EdgeColor', 'none');
h50 = fill([xi(idx50), fliplr(xi(idx50))], [f(idx50), zeros(1, nnz(idx50))], blue_mid, 'EdgeColor', 'none');
plot(xi, f, 'Color', blue_dark, 'LineWidth', 1.5);
hmed = xline(pct(3), '-', 'Color', blue_dark, 'LineWidth', 2);
hold off;

xlabel(xlab);
ylabel('Density');
title(tile_title, 'Interpreter', 'none');
grid on;
if nargin >= 4 && ~isempty(xrange)
    xlim(xrange);
end

end
