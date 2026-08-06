function [dataM_stand, dataQ_stand, meansM, meansQ, stdsM, stdsQ, flag_usestartvalsM, flag_usestartvalsQ, dates] = f_growth_rates(dataM_sa, dataQ_sa, namesM, namesQ, dates)

% Converts SA (or pass-through raw) levels into growth rates -- month-on-
% month for monthly series, quarter-on-quarter for quarterly-native series
% (frequency read off the row's own NaN pattern: skipping NaNs before
% differencing naturally compresses a dequartered row to its quarter-end
% observations only, so one transform works for both frequencies) -- except
% FIRST_DIFF_ONLY, which are first-differenced instead of turned into growth
% rates. Standardizes each series (mean/std ignoring NaN) and truncates the
% sample to SAMPLE_START onwards.
%
% dataM_sa, dataQ_sa, namesM, namesQ, dates are the outputs of load_data()
% (raw levels, mnemonics, full-history dates) after f_seasonal_adjust() has
% substituted SA levels for the fiscal series.
%
%   dataM_stand, dataQ_stand   : standardized growth rates, variables x time
%   meansM/Q, stdsM/Q          : per-variable mean/std used to standardize
%   flag_usestartvalsM/Q       : all zero (no starting-value source data
%                                 exists for this dataset)
%   dates                      : 1 x T, truncated to SAMPLE_START onwards

SAMPLE_START = 1996;

% Already rates/indices, not flows -- first-differenced rather than turned
% into a growth rate.
FIRST_DIFF_ONLY = {'IFO_BIZCLIMATE_M', 'BUND_YIELD_10Y_M'};

dataM = f_transform_all(dataM_sa, namesM, FIRST_DIFF_ONLY);
dataQ = f_transform_all(dataQ_sa, namesQ, FIRST_DIFF_ONLY);

idx_keep = find(dates >= SAMPLE_START);
dataM = dataM(:, idx_keep);
dataQ = dataQ(:, idx_keep);
dates = dates(idx_keep);

[dataM_stand, meansM, stdsM] = f_standardize(dataM);
[dataQ_stand, meansQ, stdsQ] = f_standardize(dataQ);

flag_usestartvalsM = zeros(1, numel(namesM));
flag_usestartvalsQ = zeros(1, numel(namesQ));

end


function data_out = f_transform_all(data, names, first_diff_only)
data_out = NaN(size(data));
for n = 1 : size(data, 1)
    if ismember(names{n}, first_diff_only)
        data_out(n, :) = f_transform_row(data(n, :), 'diff');
    else
        data_out(n, :) = f_transform_row(data(n, :), 'growth');
    end
end
end


function out = f_transform_row(row, transform_type)
idx_valid = find(~isnan(row));
out = NaN(size(row));
if numel(idx_valid) < 2
    return;
end
vals = row(idx_valid);
if strcmp(transform_type, 'diff')
    d = [NaN, diff(vals)];
else
    d = [NaN, (vals(2:end) ./ vals(1:end-1) - 1) * 100];
end
out(idx_valid) = d;
end


function [data_stand, means, stds] = f_standardize(data)
data_stand = NaN(size(data));
means = NaN(1, size(data, 1));
stds = NaN(1, size(data, 1));
for n = 1 : size(data, 1)
    means(n) = mean(data(n, :), 'omitnan');
    stds(n) = std(data(n, :), 'omitnan');
    data_stand(n, :) = (data(n, :) - means(n)) / stds(n);
end
end
