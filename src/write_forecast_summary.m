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
rev_pctiles = prctile(postproc.balance_to_gdp.rev_pct,   [25 50 75], 2);
exp_pctiles = prctile(postproc.balance_to_gdp.exp_pct,   [25 50 75], 2);

% --- merge onto the union of their quarters --------------------------------
% Ragged edge: GDP can already be published for a quarter whose fiscal data
% are still being forecast (or vice versa). Such quarters get the actual
% value, marked "(actual)", or "--" if no actual is available.

all_dates = union(gdp_dates, bal_dates);
hist_qend = snap_qend(dates_dt - calmonths(1));

lines = {'| Quarter | Real GDP, q/q (%) | GG balance (% of GDP) | GG revenues (% of GDP) | GG expenditures (% of GDP) |', ...
         '|---|---|---|---|---|'};
fmt_pct = @(r) sprintf('%.1f [%.1f, %.1f]', r(2), r(1), r(3));
for k = 1 : numel(all_dates)
    d   = all_dates(k);
    qtr = sprintf('%dQ%d', year(d), ceil(month(d) / 3));

    i_gdp = find(gdp_dates == d);
    if ~isempty(i_gdp)
        r = gdp_pctiles(i_gdp, :);
        gdp_cell = sprintf('%.1f [%.1f, %.1f]', r(2), r(1), r(3));
    else
        idx_act = find(hist_qend == d & ~isnan(dataQ_restand(i, :)), 1, 'last');
        if isempty(idx_act)
            gdp_cell = '--';
        else
            gdp_cell = sprintf('%.1f (actual)', dataQ_restand(i, idx_act));
        end
    end

    i_bal = find(bal_dates == d);
    if ~isempty(i_bal)
        bal_cell = fmt_pct(bal_pctiles(i_bal, :));
        rev_cell = fmt_pct(rev_pctiles(i_bal, :));
        exp_cell = fmt_pct(exp_pctiles(i_bal, :));
    else
        [bal_cell, rev_cell, exp_cell] = deal('--');
    end

    lines{end + 1} = sprintf('| %s | %s | %s | %s | %s |', qtr, gdp_cell, bal_cell, rev_cell, exp_cell);
end

out_file = fullfile(outpath, 'forecast_summary.md');
fid = fopen(out_file, 'w');
fprintf(fid, '%s\n', lines{:});
fclose(fid);

end
