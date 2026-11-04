function export_forecast_html(draws, postproc, dataQ_restand, dates, namesQ, dataQ_sa, ngdp_raw_eur, dates_full, vintagedate, outpath, hist_start_year)

% Writes output/forecast_dashboard.html: a single self-contained, shareable
% HTML file (no MATLAB, no internet needed to view it) with interactive fan
% charts -- hover shows the median and 50%/95% intervals per quarter -- for
% real GDP q/q growth and the GG balance, revenues and expenditures (% of
% nominal GDP), plus a forecast summary table and a CSV download of all
% numbers.
%
% Same numbers as the PNGs/markdown: GDP as in plot_gdp_deficit.m, balance /
% revenues / expenditures from postproc.balance_to_gdp (f_postprocess_draws.m),
% history for revenues/expenditures as in plot_rev_exp.m.
%
% Page layout and chart code live in src/forecast_dashboard_template.html;
% Plotly.js is inlined from tools/plotly-basic-2.35.2.min.js.
%
% Inputs:
%   draws, postproc, dataQ_restand, dates, namesQ : as in plot_gdp_deficit.m
%   dataQ_sa, ngdp_raw_eur, dates_full            : as in plot_rev_exp.m
%   vintagedate     : data vintage (last month of the monthly grid), from
%                      load_sa_data().
%   outpath         : directory to write 'forecast_dashboard.html' into.
%   hist_start_year : earliest year (year + (month-1)/12) of history shown,
%                      or omitted/[] for all history.

if nargin < 11 || isempty(hist_start_year)
    hist_start_year = -Inf;
end

PCT = [2.5 25 50 75 97.5];

src_dir    = fileparts(mfilename('fullpath'));
tmpl_file  = fullfile(src_dir, 'forecast_dashboard_template.html');
plotly_file = fullfile(src_dir, '..', 'tools', 'plotly-basic-2.35.2.min.js');

PLOTLY_URL = 'https://cdn.jsdelivr.net/npm/plotly.js-basic-dist-min@2.35.2/plotly-basic.min.js';

% tools/ is git-ignored (downloaded, not tracked): fetch the pinned Plotly
% bundle once if it isn't there yet. Only needed when *generating* the HTML;
% the finished file embeds it and works offline.
if ~isfile(plotly_file)
    if ~isfolder(fileparts(plotly_file))
        mkdir(fileparts(plotly_file));
    end
    websave(plotly_file, PLOTLY_URL);
end

snap_qend = @(dt) datetime(year(dt), ceil(month(dt) / 3) * 3, 1);

% --- real GDP q/q growth (same construction as plot_gdp_deficit.m) --------

i_gdp = find(strcmp(namesQ, 'GDP_REAL_Q'));
if isempty(i_gdp)
    error('export_forecast_html: GDP_REAL_Q not found among quarterly variables.');
end
dt_m     = f_to_dt(dates);
idx_obs  = find(~isnan(dataQ_restand(i_gdp, :)));
idx_hist = idx_obs(dates(idx_obs) >= hist_start_year);
gdp_hist_dt = snap_qend(dt_m(idx_hist) - calmonths(1));
gdp_hist_v  = dataQ_restand(i_gdp, idx_hist);

Hq_max  = size(draws.forecasts_restand, 1);
Hq_i    = draws.Hq(i_gdp);
j_start = Hq_max - Hq_i + 1;
last_dt = snap_qend(dt_m(idx_obs(end)) - calmonths(1));
gdp_fc_dt = last_dt + calmonths(3 * (1 : Hq_i));
gdp_fc_p  = prctile(reshape(draws.forecasts_restand(j_start:Hq_max, i_gdp, :), Hq_i, []), PCT, 2);

series = {};
series{end + 1} = f_series('gdp', 'Real GDP', 'Real GDP', '% q/q', ...
                           gdp_hist_dt, gdp_hist_v, gdp_fc_dt, gdp_fc_p);

% --- balance, revenues, expenditures as % of nominal GDP -------------------

dt_q   = f_to_dt(dates_full);
in_win = dates_full >= hist_start_year;
bg     = postproc.balance_to_gdp;

i_rev = find(strcmp(namesQ, 'REV_GG_TOTAL_Q'));
i_exp = find(strcmp(namesQ, 'EXP_GG_TOTAL_Q'));

hist_bal = bg.hist_ratio_pct;
hist_rev = 100 * dataQ_sa(i_rev, :) ./ ngdp_raw_eur;
hist_exp = 100 * dataQ_sa(i_exp, :) ./ ngdp_raw_eur;

specs = { ...
    'balance',      'General government balance',      'GG balance',      hist_bal, bg.ratio_pct; ...
    'revenues',     'General government revenues',     'GG revenues',     hist_rev, bg.rev_pct; ...
    'expenditures', 'General government expenditures', 'GG expenditures', hist_exp, bg.exp_pct};

for k = 1 : size(specs, 1)
    h   = specs{k, 4};
    idx = find(~isnan(h) & in_win);
    series{end + 1} = f_series(specs{k, 1}, specs{k, 2}, specs{k, 3}, '% of GDP', ...
                               dt_q(idx), h(idx), bg.dates, prctile(specs{k, 5}, PCT, 2)); %#ok<AGROW>
end

% --- assemble JSON and write the HTML --------------------------------------

if isdatetime(vintagedate)
    vint_dt = vintagedate;
else
    vint_dt = datetime(vintagedate, 'ConvertFrom', 'datenum');
end
meta.vintage    = char(string(vint_dt, 'MMM yyyy'));
meta.vintage_id = char(string(vint_dt, 'yyyy-MM'));
meta.generated  = char(string(datetime('now'), 'dd MMM yyyy'));

data.meta   = meta;
data.series = [series{:}];

json = jsonencode(data);
json = strrep(json, '</', '<\/');  % keep the JSON from closing its <script> tag

html   = f_read_utf8(tmpl_file);
plotly = f_read_utf8(plotly_file);
plotly = strrep(plotly, '</script', '<\/script');

html = f_replace_once(html, '/*__FORECAST_DATA__*/', json);
html = f_replace_once(html, '/*__PLOTLY_JS__*/', plotly);

out_file = fullfile(outpath, 'forecast_dashboard.html');
fid = fopen(out_file, 'w', 'n', 'UTF-8');
if fid < 0
    error('export_forecast_html: cannot open %s for writing.', out_file);
end
fprintf(fid, '%s', html);
fclose(fid);

end


function txt = f_read_utf8(file)
fid = fopen(file, 'r', 'n', 'UTF-8');
if fid < 0
    error('export_forecast_html: cannot read %s.', file);
end
txt = fread(fid, [1 Inf], '*char');
fclose(fid);
end


function s = f_series(id, title, short, unit, hist_dt, hist_v, fc_dt, fc_p)
% fc_p: Hq x 5 percentiles [2.5 25 50 75 97.5]. Values rounded to 3 dp to keep
% the file small; labels are 'YYYYQn'. Single values are wrapped in cells so
% jsonencode always emits arrays.
s.id    = id;
s.title = title;
s.short = short;
s.unit  = unit;
s.hist.q = f_qlabels(hist_dt);
s.hist.v = num2cell(round(hist_v(:)', 3));
s.fc.q    = f_qlabels(fc_dt);
s.fc.p025 = num2cell(round(fc_p(:, 1)', 3));
s.fc.p25  = num2cell(round(fc_p(:, 2)', 3));
s.fc.p50  = num2cell(round(fc_p(:, 3)', 3));
s.fc.p75  = num2cell(round(fc_p(:, 4)', 3));
s.fc.p975 = num2cell(round(fc_p(:, 5)', 3));
end


function lbl = f_qlabels(dt)
lbl = arrayfun(@(d) sprintf('%dQ%d', year(d), ceil(month(d) / 3)), dt(:)', 'UniformOutput', false);
end


function dt = f_to_dt(dates)
yr = floor(dates);
mo = round((dates - yr) * 12) + 1;
dt = datetime(yr, mo, 1);
end


function out = f_replace_once(str, token, repl)
k = strfind(str, token);
if numel(k) ~= 1
    error('export_forecast_html: expected exactly one %s in the template, found %d.', token, numel(k));
end
out = [str(1 : k - 1), repl, str(k + numel(token) : end)];
end
