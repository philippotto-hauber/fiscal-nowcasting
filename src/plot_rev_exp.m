function plot_rev_exp(postproc, dataQ_sa, namesQ, ngdp_raw_eur, dates_full, outpath, hist_start_year)

% Plots two fan charts (as tiles in one figure), both history + forecast:
% general government revenues (REV_GG_TOTAL_Q) and expenditures
% (EXP_GG_TOTAL_Q) as a percent of nominal GDP. Same definition as the
% balance ratio in f_postprocess_draws.m (so revenues - expenditures here
% equals the balance-to-GDP ratio in plot_gdp_deficit.m):
%   history  : 100 x SA level / raw GDP_NOMINAL_Q (EUR), actuals only.
%   forecast : 100 x SA level draw / EUR-rescaled implied nominal GDP draw
%              (postproc.ngdp.levels_nom_eur), per MCMC draw.
% Same look as plot_gdp_deficit.m (shared f_plot_fan.m).
%
% Inputs:
%   postproc         : output of f_postprocess_draws.m; uses .balance
%                       (.dates, .levels_rev, .levels_exp) and .ngdp
%                       (.dates, .levels_nom_eur).
%   dataQ_sa         : quarterly SA levels, variables x time (raw EUR for
%                       the two fiscal series), as passed to
%                       f_postprocess_draws.m in main.m.
%   namesQ           : quarterly mnemonics matching dataQ_sa's rows.
%   ngdp_raw_eur     : 1 x T, raw (source-SA) nominal GDP level, EUR,
%                       matching dataQ_sa's time axis (see main.m).
%   dates_full       : 1 x T, year + (month-1)/12, matching dataQ_sa's
%                       time axis (load_raw_data()'s dates_full).
%   outpath          : directory to save 'fcasts_rev_exp.png' into, or
%                       ''/omitted to skip saving.
%   hist_start_year  : earliest year (as year + (month-1)/12) of history to
%                       plot, or omitted/[] for all history.

if nargin < 6 || isempty(outpath)
    outpath = '';
end
if nargin < 7 || isempty(hist_start_year)
    hist_start_year = -Inf;
end

yr_all   = floor(dates_full);
mo_all   = round((dates_full - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

% Forecast quarters with both a fiscal and a nominal-GDP draw.
[in_gdp, i_gdp] = ismember(postproc.balance.dates, postproc.ngdp.dates);
fc_dates = postproc.balance.dates(in_gdp);
fc_ngdp  = postproc.ngdp.levels_nom_eur(i_gdp(in_gdp), :);

panels = { ...
    'REV_GG_TOTAL_Q', postproc.balance.levels_rev(in_gdp, :), 'General government revenues, % of nominal GDP'; ...
    'EXP_GG_TOTAL_Q', postproc.balance.levels_exp(in_gdp, :), 'General government expenditures, % of nominal GDP'};

figure;
tiledlayout(2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

for p = 1 : size(panels, 1)
    i = find(strcmp(namesQ, panels{p, 1}));
    if isempty(i)
        error('plot_rev_exp: %s not found among quarterly variables.', panels{p, 1});
    end

    nexttile;
    hist_ratio = 100 * dataQ_sa(i, :) ./ ngdp_raw_eur;
    idx_hist   = find(~isnan(hist_ratio) & dates_full >= hist_start_year);

    fc_pctiles = prctile(100 * panels{p, 2} ./ fc_ngdp, [2.5 25 50 75 97.5], 2);

    [hhist, hmed, h50, h95] = f_plot_fan(dates_dt(idx_hist), hist_ratio(idx_hist), fc_dates, fc_pctiles);
    title(panels{p, 3}, 'Interpreter', 'none');
    ylabel('% of GDP');
end

lgd = legend([hhist, hmed, h50, h95], ...
             'Historical', 'Median forecast', '50% interval', '95% interval', ...
             'Orientation', 'horizontal');
lgd.Layout.Tile = 'south';

if ~isempty(outpath)
    exportgraphics(gcf, fullfile(outpath, 'fcasts_rev_exp.png'));
end
end
