function [hhist, hmed, h50, h95] = f_plot_fan(hist_dates_dt, hist_vals, forecast_dates, forecast_pctiles)

% Plots a fan chart onto the current axes: history (optional) bridged into
% a forecast median line with 50%/95% probability bands.
%
% Inputs:
%   hist_dates_dt, hist_vals : historical datetime vector and values. Pass
%                              [] for both to plot a forecast-only fan, with
%                              no history line and no bridge point (used for
%                              derived quantities with no historical series
%                              of their own, e.g. the deficit-to-GDP ratio
%                              in f_postprocess_draws.m).
%   forecast_dates           : 1 x Hq forecast quarter-end datetimes.
%   forecast_pctiles         : Hq x 5, columns = [2.5 25 50 75 97.5]
%                              percentiles.
%
% Returns the plotted graphics handles; hhist is an empty graphics array
% (gobjects(0)) when no history is supplied.

blue_dark  = [0.13 0.47 0.71];
blue_mid   = [0.53 0.75 0.90];
blue_light = [0.78 0.89 0.95];

hold on;

has_hist = ~isempty(hist_dates_dt);

if has_hist
    last_hist_dt  = hist_dates_dt(end);
    last_hist_val = hist_vals(end);
    dates_ext = [last_hist_dt, forecast_dates];
    p025_ext  = [last_hist_val, forecast_pctiles(:, 1)'];
    p25_ext   = [last_hist_val, forecast_pctiles(:, 2)'];
    p50_ext   = [last_hist_val, forecast_pctiles(:, 3)'];
    p75_ext   = [last_hist_val, forecast_pctiles(:, 4)'];
    p975_ext  = [last_hist_val, forecast_pctiles(:, 5)'];
else
    dates_ext = forecast_dates;
    p025_ext  = forecast_pctiles(:, 1)';
    p25_ext   = forecast_pctiles(:, 2)';
    p50_ext   = forecast_pctiles(:, 3)';
    p75_ext   = forecast_pctiles(:, 4)';
    p975_ext  = forecast_pctiles(:, 5)';
end

h95 = fill([dates_ext, fliplr(dates_ext)], [p025_ext, fliplr(p975_ext)], ...
           blue_light, 'EdgeColor', 'none');
h50 = fill([dates_ext, fliplr(dates_ext)], [p25_ext, fliplr(p75_ext)], ...
           blue_mid, 'EdgeColor', 'none');
hmed = plot(dates_ext, p50_ext, '-o', 'Color', blue_dark, ...
            'LineWidth', 1.5, 'MarkerSize', 4);

if has_hist
    hhist = plot(hist_dates_dt, hist_vals, '-o', ...
                 'Color', 'k', 'LineWidth', 1.5, 'MarkerSize', 4);
    xline(last_hist_dt, '--k', 'LineWidth', 1);
else
    hhist = gobjects(0);
end

xtick_pos = [hist_dates_dt, forecast_dates];
xtick_lbl = cell(1, length(xtick_pos));
for jj = 1 : length(xtick_pos)
    xtick_lbl{jj} = sprintf('%dQ%d', year(xtick_pos(jj)), ceil(month(xtick_pos(jj)) / 3));
end
set(gca, 'XTick', xtick_pos, 'XTickLabel', xtick_lbl, 'XTickLabelRotation', 45);
grid on;
hold off;
end
