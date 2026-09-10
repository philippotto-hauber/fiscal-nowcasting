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
