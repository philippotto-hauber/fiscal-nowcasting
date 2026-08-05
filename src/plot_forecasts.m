function plot_forecasts(draws, dataQ_restand, dates, options, namesQ, groupsQ, outpath, vars_to_plot, hist_start_year)

if nargin < 7
    outpath = '';
end
if nargin < 9 || isempty(hist_start_year)
    hist_start_year = -Inf;
end

if nargin < 8 || isempty(vars_to_plot)
    plot_idx = 1 : options.Nq;
else
    plot_idx = find(ismember(namesQ, vars_to_plot));
    if isempty(plot_idx)
        warning('plot_forecasts: none of the requested variable names found in namesQ.');
        return;
    end
end

Hq_max = size(draws.forecasts_restand, 1);

% Convert float dates (yr + (month-1)/12) to datetime objects
yr_all   = floor(dates);
mo_all   = round((dates - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

% Snap a datetime to the last month of its quarter (3, 6, 9, or 12)
snap_qend = @(dt) datetime(year(dt), ceil(month(dt) / 3) * 3, 1);

pctiles = prctile(draws.forecasts_restand, [2.5 25 50 75 97.5], 3);

blue_dark  = [0.13 0.47 0.71];
blue_mid   = [0.53 0.75 0.90];
blue_light = [0.78 0.89 0.95];

n_plots = length(plot_idx);
figure;
tiledlayout(n_plots, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
leg_handles = [];

for k = 1 : n_plots
    i = plot_idx(k);
    nexttile;
    hold on;

    idx_Q_i  = find(~isnan(dataQ_restand(i, :)));
    idx_plot = idx_Q_i(dates(idx_Q_i) >= hist_start_year);

    last_hist_dt  = snap_qend(dates_dt(idx_Q_i(end)) - calmonths(1));
    last_hist_val = dataQ_restand(i, idx_Q_i(end));

    Hq_i    = draws.Hq(i);
    j_start = Hq_max - Hq_i + 1;

    % Per-variable forecast datetimes: uniform 3-month steps from last observation
    datesQ_i = last_hist_dt + calmonths(3 * (1 : Hq_i));

    p025 = reshape(pctiles(j_start:Hq_max, i, 1), 1, []);
    p25  = reshape(pctiles(j_start:Hq_max, i, 2), 1, []);
    p50  = reshape(pctiles(j_start:Hq_max, i, 3), 1, []);
    p75  = reshape(pctiles(j_start:Hq_max, i, 4), 1, []);
    p975 = reshape(pctiles(j_start:Hq_max, i, 5), 1, []);

    datesQ_ext = [last_hist_dt, datesQ_i];
    p025_ext   = [last_hist_val, p025];
    p25_ext    = [last_hist_val, p25];
    p50_ext    = [last_hist_val, p50];
    p75_ext    = [last_hist_val, p75];
    p975_ext   = [last_hist_val, p975];

    h95 = fill([datesQ_ext, fliplr(datesQ_ext)], [p025_ext, fliplr(p975_ext)], ...
               blue_light, 'EdgeColor', 'none');
    h50 = fill([datesQ_ext, fliplr(datesQ_ext)], [p25_ext, fliplr(p75_ext)], ...
               blue_mid, 'EdgeColor', 'none');
    hmed = plot(datesQ_ext, p50_ext, '-o', 'Color', blue_dark, ...
                'LineWidth', 1.5, 'MarkerSize', 4);
    hist_dates_dt = snap_qend(dates_dt(idx_plot) - calmonths(1));
    hhist = plot(hist_dates_dt, dataQ_restand(i, idx_plot), '-o', ...
                 'Color', 'k', 'LineWidth', 1.5, 'MarkerSize', 4);
    xline(last_hist_dt, '--k', 'LineWidth', 1);

    % Quarter labels from datetime using built-in year/month functions
    xtick_pos = [hist_dates_dt, datesQ_i];
    xtick_lbl = cell(1, length(xtick_pos));
    for jj = 1 : length(xtick_pos)
        xtick_lbl{jj} = sprintf('%dQ%d', year(xtick_pos(jj)), ceil(month(xtick_pos(jj)) / 3));
    end
    set(gca, 'XTick', xtick_pos, 'XTickLabel', xtick_lbl, 'XTickLabelRotation', 45);

    varname = [groupsQ{i} ': ' namesQ{i}];
    title(varname, 'Interpreter', 'none');
    hold off;

    if k == 1
        leg_handles = [hhist, hmed, h50, h95];
    end
end

lgd = legend(leg_handles, ...
             'Historical', 'Median forecast', '50% interval', '95% interval', ...
             'Orientation', 'horizontal');
lgd.Layout.Tile = 'south';

if ~isempty(outpath)
    exportgraphics(gcf, fullfile(outpath, 'forecasts.png'));
end
end
