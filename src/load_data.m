function [dataM_stand, dataQ_stand, meansM, meansQ, stdsM, stdsQ, flag_usestartvalsM, flag_usestartvalsQ, namesM, namesQ, groupsM, groupsQ, dates, vintagedate] = load_data()

% Loads data/dataset_estimation.csv (built by src/build_estimation_dataset.py)
% and returns the estimation inputs, split into monthly (M) and
% quarterly-native (Q) series (frequency is read off each mnemonic's _M/_Q
% suffix):
%   dataM_stand, dataQ_stand   : standardized data, variables x time
%   meansM/Q, stdsM/Q          : per-variable mean/std used to standardize
%   flag_usestartvalsM/Q       : all zero (no starting-value source data
%                                 exists for this dataset)
%   namesM/Q                   : mnemonics from the CSV header
%   groupsM/Q                  : 'fiscal' for REV_*/EXP_* mnemonics, 'macro'
%                                 otherwise
%   dates                      : 1 x T, year + (month-1)/12
%   vintagedate                : datetime of the last (most recent) row in
%                                 the CSV

repo_root = fileparts(fileparts(mfilename('fullpath')));
data_path = fullfile(repo_root, 'data', 'dataset_estimation.csv');

% ------------------------- %
% - load csv --------------- %

opts = detectImportOptions(data_path);
opts = setvartype(opts, opts.VariableNames{1}, 'char');
T = readtable(data_path, opts);

dates_dt = datetime(T{:, 1}, 'InputFormat', 'yyyy-MM-dd');
mnemonics = T.Properties.VariableNames(2:end);
data = table2array(T(:, 2:end))';  % variables x time

% ------------------------------------------------- %
% - split into monthly vs quarterly-native series - %
% (frequency is read directly off each mnemonic's _M/_Q suffix)

is_quarterly = endsWith(mnemonics, '_Q');

dataM = data(~is_quarterly, :);
dataQ = data(is_quarterly, :);

namesM = mnemonics(~is_quarterly);
namesQ = mnemonics(is_quarterly);

groupsM = cellfun(@f_group, namesM, 'UniformOutput', false);
groupsQ = cellfun(@f_group, namesQ, 'UniformOutput', false);

% -------------------------- %
% - standardize ------------ %

[dataM_stand, meansM, stdsM] = f_standardize(dataM);
[dataQ_stand, meansQ, stdsQ] = f_standardize(dataQ);

flag_usestartvalsM = zeros(1, numel(namesM));
flag_usestartvalsQ = zeros(1, numel(namesQ));

% -------------------------- %
% - dates & vintage --------- %

dates = (year(dates_dt) + (month(dates_dt) - 1) / 12)';
vintagedate = dates_dt(end);

end


function group = f_group(mnemonic)
if startsWith(mnemonic, 'REV_') || startsWith(mnemonic, 'EXP_')
    group = 'fiscal';
else
    group = 'macro';
end
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
