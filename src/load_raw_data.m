function [dataM, dataQ, namesM, namesQ, groupsM, groupsQ, dates, vintagedate] = load_raw_data()

% Loads data/trial_small_monthly.csv (raw, unadjusted levels) and returns it
% split into monthly (M) and quarterly-native (Q) series (frequency is read
% off each mnemonic's _M/_Q suffix):
%   dataM, dataQ    : raw levels, variables x time, NOT seasonally adjusted,
%                      NOT standardized (see load_sa_data.m and
%                      f_growth_rates.m for those steps)
%   namesM/Q        : mnemonics from the CSV header
%   groupsM/Q       : 'fiscal' for REV_*/EXP_* mnemonics, 'macro' otherwise
%   dates           : 1 x T, year + (month-1)/12
%   vintagedate     : datetime of the last (most recent) row in the CSV

repo_root = fileparts(fileparts(mfilename('fullpath')));
data_path = fullfile(repo_root, 'data', 'trial_small_monthly.csv');

% ------------------------- %
% - load csv --------------- %

opts = detectImportOptions(data_path);
opts = setvartype(opts, opts.VariableNames{1}, 'char');
opts = setvartype(opts, opts.VariableNames(2:end), 'double');
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
