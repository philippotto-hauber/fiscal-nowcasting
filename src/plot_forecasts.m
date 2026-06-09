function plot_forecasts(draws, dataQ_restand, dates, options, names, groups, outpath, vars_to_plot)

if nargin < 7
    outpath = '';
end

% Determine which quarterly variable indices to plot
namesQ = names(options.Nm + 1 : end);
if nargin < 8 || isempty(vars_to_plot)
    plot_idx = 1 : options.Nq;
else
    plot_idx = find(ismember(namesQ, vars_to_plot));
    if isempty(plot_idx)
        warning('plot_forecasts: none of the requested variable names found in namesQ.');
        return;
    end
end

% Last quarter-end date in the sample (use actual dates array value for precision)
all_months_sample = round((dates - floor(dates)) * 12) + 1;
last_qend_idx     = find(ismember(all_months_sample, [3 6 9 12]), 1, 'last');
last_datesQ       = dates(last_qend_idx);

% Forecast dates in quarter-START convention (Jan, Apr, Jul, Oct) to match
% how quarterly variables are stored in the dataset. Shift last quarter-end
% (e.g. March 2026) by +1 month to get the first forecast quarter-start
% (April 2026 = Q2 2026), then step forward in 3-month increments.
H           = ceil(options.Nh / 3);
datesQ_fore = last_datesQ + 1/12 + (0 : H-1) * (3/12);

% Percentiles across MCMC draws: [H x Nq x 5]
% Columns: 2.5, 25, 50, 75, 97.5 -> 95% and 50% intervals around median
pctiles = prctile(draws.forecasts_restand, [2.5 25 50 75 97.5], 3);

% Colors
blue_dark  = [0.13 0.47 0.71];
blue_mid   = [0.53 0.75 0.90];
blue_light = [0.78 0.89 0.95];

n_hist_Q = 16; % ~4 years of quarterly history to display
n_plots  = length(plot_idx);

figure;
tiledlayout(n_plots, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

leg_handles = [];

for k = 1 : n_plots
    i = plot_idx(k);
    nexttile;
    hold on;

    % Historical quarterly observations for this variable
    idx_Q_i  = find(~isnan(dataQ_restand(i, :)));
    n_show   = min(n_hist_Q, length(idx_Q_i));
    idx_plot = idx_Q_i(end - n_show + 1 : end);

    % Anchor blue forecast line at last historical observation
    last_hist_date = dates(idx_Q_i(end));
    last_hist_val  = dataQ_restand(i, idx_Q_i(end));

    % Skip forecast quarters already covered by this variable's historical data
    % (e.g. GDP has Q2 2026 observed so its first unobserved forecast is Q3)
    skip          = sum(datesQ_fore <= last_hist_date + 1e-9);
    datesQ_fore_i = datesQ_fore(skip + 1 : end);

    % Extended forecast dates: anchor at last known value so fan chart
    % opens from there and blue line connects to historical data
    datesQ_ext = [last_hist_date, datesQ_fore_i];

    % Percentiles for unobserved forecast quarters only
    p025 = squeeze(pctiles(skip+1:end, i, 1))';
    p25  = squeeze(pctiles(skip+1:end, i, 2))';
    p50  = squeeze(pctiles(skip+1:end, i, 3))';
    p75  = squeeze(pctiles(skip+1:end, i, 4))';
    p975 = squeeze(pctiles(skip+1:end, i, 5))';

    % Extended with anchor (uncertainty = 0 at last known value)
    p025_ext = [last_hist_val, p025];
    p25_ext  = [last_hist_val, p25];
    p50_ext  = [last_hist_val, p50];
    p75_ext  = [last_hist_val, p75];
    p975_ext = [last_hist_val, p975];

    % Fan chart bands (fan opens from last known value)
    h95 = fill([datesQ_ext, fliplr(datesQ_ext)], [p025_ext, fliplr(p975_ext)], ...
               blue_light, 'EdgeColor', 'none');
    h50 = fill([datesQ_ext, fliplr(datesQ_ext)], [p25_ext, fliplr(p75_ext)], ...
               blue_mid, 'EdgeColor', 'none');

    % Median forecast (dark blue) starting from last historical value
    hmed  = plot(datesQ_ext, p50_ext, '-o', 'Color', blue_dark, ...
                 'LineWidth', 1.5, 'MarkerSize', 4);

    % Historical data in black, overwrites the blue anchor point
    hhist = plot(dates(idx_plot), dataQ_restand(i, idx_plot), '-o', ...
                 'Color', 'k', 'LineWidth', 1.5, 'MarkerSize', 4);

    % Vertical line at last available observation for this variable
    xline(last_hist_date, '--k', 'LineWidth', 1);

    % X-axis: use exact plotted date values as tick positions so ticks and
    % data points align perfectly, then label as YYYYQq
    xtick_pos = [dates(idx_plot), datesQ_fore_i];
    xtick_lbl = cell(1, length(xtick_pos));
    for j = 1 : length(xtick_pos)
        yr = floor(xtick_pos(j));
        mo = round((xtick_pos(j) - yr) * 12) + 1;
        xtick_lbl{j} = sprintf('%dQ%d', yr, ceil(mo / 3));
    end
    set(gca, 'XTick', xtick_pos, 'XTickLabel', xtick_lbl, 'XTickLabelRotation', 45);

    varname = [groups{options.Nm + i} ': ' names{options.Nm + i}];
    title(varname, 'Interpreter', 'none');
    hold off;

    if k == 1
        leg_handles = [hhist, hmed, h50, h95];
    end
end

% Shared legend placed below all tiles
lgd = legend(leg_handles, ...
             'Historical', 'Median forecast', '50% interval', '95% interval', ...
             'Orientation', 'horizontal');
lgd.Layout.Tile = 'south';

if ~isempty(outpath)
    exportgraphics(gcf, fullfile(outpath, 'forecasts.png'));
end
end
