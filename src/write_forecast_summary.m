function write_forecast_summary(draws, postproc, dataQ_restand, dates, namesQ, outpath)

% Writes output/forecast_summary.md: for every forecast quarter common to
% both series, the median and 50% predictive interval ([p25, p75]) of real
% GDP q/q growth and the general government balance (% of nominal GDP).
% Markdown (not CSV) since each cell is a formatted "median [p25, p75]"
% string meant to be read, not parsed -- see plot_gdp_deficit.m for the
% fan-chart version of the same two series, and f_postprocess_draws.m for
% how the balance-to-GDP ratio is derived.
%
% Inputs:
%   draws            : must have fields .forecasts_restand (Hq_max x Nq x
%                       Ndraws, destandardized q/q growth rate (%)
%                       forecasts) and .Hq (1 x Nq, per-variable forecast
%                       horizon in quarters) -- both set by GibbsSampler.m.
%   postproc         : output of f_postprocess_draws.m; only
%                       .balance_to_gdp (.dates, .ratio_pct) is used here.
%   dataQ_restand    : destandardized quarterly SA q/q growth rates,
%                       variables x time (dataQ_stand .* stdsQ' + meansQ',
%                       as computed in main.m).
%   dates            : 1 x T, year + (month-1)/12, matching
%                       dataQ_restand's time axis.
%   namesQ           : quarterly mnemonics matching dataQ_restand's rows
%                       and draws' columns.
%   outpath          : directory to write forecast_summary.md into.

GDP_VAR = 'GDP_REAL_Q';

i = find(strcmp(namesQ, GDP_VAR));
if isempty(i)
    error('write_forecast_summary: %s not found among quarterly variables.', GDP_VAR);
end

Hq_max = size(draws.forecasts_restand, 1);

yr_all    = floor(dates);
mo_all    = round((dates - yr_all) * 12) + 1;
dates_dt  = datetime(yr_all, mo_all, 1);
snap_qend = @(dt) datetime(year(dt), ceil(month(dt) / 3) * 3, 1);

pctiles = prctile(draws.forecasts_restand, [25 50 75], 3);

% --- real GDP q/q growth, forecast quarters + [p25 p50 p75] ---------------

idx_Q_i      = find(~isnan(dataQ_restand(i, :)));
Hq_i         = draws.Hq(i);
j_start      = Hq_max - Hq_i + 1;
last_hist_dt = snap_qend(dates_dt(idx_Q_i(end)) - calmonths(1));

gdp_dates   = last_hist_dt + calmonths(3 * (1 : Hq_i));
gdp_pctiles = reshape(pctiles(j_start:Hq_max, i, :), Hq_i, 3);  % [p25 p50 p75]

% --- GG balance, % of nominal GDP, forecast quarters + [p25 p50 p75] ------

bal_dates   = postproc.balance_to_gdp.dates;
bal_pctiles = prctile(postproc.balance_to_gdp.ratio_pct, [25 50 75], 2);  % [p25 p50 p75]

% --- merge onto their common quarters --------------------------------------

[common_dates, i_gdp, i_bal] = intersect(gdp_dates, bal_dates);
if isempty(common_dates)
    error('write_forecast_summary: GDP and balance forecasts share no common quarter.');
end

lines = {'| Quarter | Real GDP, q/q (%) | GG balance (% of GDP) |', ...
         '|---|---|---|'};
for k = 1 : numel(common_dates)
    qtr     = sprintf('%dQ%d', year(common_dates(k)), ceil(month(common_dates(k)) / 3));
    gdp_row = gdp_pctiles(i_gdp(k), :);
    bal_row = bal_pctiles(i_bal(k), :);
    lines{end + 1} = sprintf('| %s | %.1f [%.1f, %.1f] | %.1f [%.1f, %.1f] |', ...
        qtr, gdp_row(2), gdp_row(1), gdp_row(3), bal_row(2), bal_row(1), bal_row(3));
end

out_file = fullfile(outpath, 'forecast_summary.md');
fid = fopen(out_file, 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);

end
