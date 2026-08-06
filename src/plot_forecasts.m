function plot_forecasts(draws, dataQ_restand, dates, options, namesQ, groupsQ, outpath, vars_to_plot, hist_start_year, forecasts_nsa, dataQ_raw, dates_full)

if nargin < 7 || isempty(outpath)
    outpath = '';
end
if nargin < 9 || isempty(hist_start_year)
    hist_start_year = -Inf;
end
if nargin < 10 || isempty(forecasts_nsa)
    forecasts_nsa = struct();
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

if nargin >= 12 && ~isempty(dates_full)
    yr_full  = floor(dates_full);
    mo_full  = round((dates_full - yr_full) * 12) + 1;
    dates_full_dt = datetime(yr_full, mo_full, 1);
end

% Snap a datetime to the last month of its quarter (3, 6, 9, or 12)
snap_qend = @(dt) datetime(year(dt), ceil(month(dt) / 3) * 3, 1);

pctiles = prctile(draws.forecasts_restand, [2.5 25 50 75 97.5], 3);

n_plots = length(plot_idx);
figure;
tiledlayout(n_plots, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
leg_handles = [];

for k = 1 : n_plots
    i = plot_idx(k);
    nexttile;

    if isfield(forecasts_nsa, namesQ{i})
        % --- reseasonalized (NSA) level: history + forecast ---
        fc = forecasts_nsa.(namesQ{i});
        idx_obs = find(~isnan(dataQ_raw(i, :)) & dates_full >= hist_start_year);
        hist_dates_dt   = dates_full_dt(idx_obs);
        hist_vals       = dataQ_raw(i, idx_obs);
        forecast_dates  = fc.dates;
        forecast_pctiles = prctile(fc.levels_nsa, [2.5 25 50 75 97.5], 2);
        varname   = [groupsQ{i} ': ' namesQ{i} ' -- level (NSA)'];
        ylabel_str = 'EUR';
    else
        % --- seasonally adjusted q/q growth rate: history + forecast ---
        idx_Q_i  = find(~isnan(dataQ_restand(i, :)));
        idx_plot = idx_Q_i(dates(idx_Q_i) >= hist_start_year);
        hist_dates_dt = snap_qend(dates_dt(idx_plot) - calmonths(1));
        hist_vals     = dataQ_restand(i, idx_plot);

        Hq_i    = draws.Hq(i);
        j_start = Hq_max - Hq_i + 1;
        last_hist_dt = snap_qend(dates_dt(idx_Q_i(end)) - calmonths(1));
        forecast_dates   = last_hist_dt + calmonths(3 * (1 : Hq_i));
        forecast_pctiles = reshape(pctiles(j_start:Hq_max, i, :), Hq_i, 5);
        varname    = [groupsQ{i} ': ' namesQ{i}];
        ylabel_str = 'q/q (%)';
    end

    [hhist, hmed, h50, h95] = f_plot_fan(hist_dates_dt, hist_vals, forecast_dates, forecast_pctiles);
    title(varname, 'Interpreter', 'none');
    ylabel(ylabel_str);

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


function [hhist, hmed, h50, h95] = f_plot_fan(hist_dates_dt, hist_vals, forecast_dates, forecast_pctiles)
% forecast_pctiles: Hq x 5, columns = [2.5 25 50 75 97.5] percentiles

blue_dark  = [0.13 0.47 0.71];
blue_mid   = [0.53 0.75 0.90];
blue_light = [0.78 0.89 0.95];

hold on;

last_hist_dt  = hist_dates_dt(end);
last_hist_val = hist_vals(end);

dates_ext = [last_hist_dt, forecast_dates];
p025_ext  = [last_hist_val, forecast_pctiles(:, 1)'];
p25_ext   = [last_hist_val, forecast_pctiles(:, 2)'];
p50_ext   = [last_hist_val, forecast_pctiles(:, 3)'];
p75_ext   = [last_hist_val, forecast_pctiles(:, 4)'];
p975_ext  = [last_hist_val, forecast_pctiles(:, 5)'];

h95 = fill([dates_ext, fliplr(dates_ext)], [p025_ext, fliplr(p975_ext)], ...
           blue_light, 'EdgeColor', 'none');
h50 = fill([dates_ext, fliplr(dates_ext)], [p25_ext, fliplr(p75_ext)], ...
           blue_mid, 'EdgeColor', 'none');
hmed = plot(dates_ext, p50_ext, '-o', 'Color', blue_dark, ...
            'LineWidth', 1.5, 'MarkerSize', 4);
hhist = plot(hist_dates_dt, hist_vals, '-o', ...
             'Color', 'k', 'LineWidth', 1.5, 'MarkerSize', 4);
xline(last_hist_dt, '--k', 'LineWidth', 1);

xtick_pos = [hist_dates_dt, forecast_dates];
xtick_lbl = cell(1, length(xtick_pos));
for jj = 1 : length(xtick_pos)
    xtick_lbl{jj} = sprintf('%dQ%d', year(xtick_pos(jj)), ceil(month(xtick_pos(jj)) / 3));
end
set(gca, 'XTick', xtick_pos, 'XTickLabel', xtick_lbl, 'XTickLabelRotation', 45);
grid on;
hold off;
end
