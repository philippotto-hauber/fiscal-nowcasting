function [dataM_sa, dataQ_sa, namesM, namesQ, groupsM, groupsQ, dates, vintagedate] = load_sa_data()

% Loads the same data as load_raw_data(), then substitutes precomputed
% X-13ARIMA-SEATS seasonally adjusted levels (from data/fiscal_sa_levels.csv,
% built by src/build_fiscal_sa_levels.py) for the 5 fiscal mnemonics. Every
% other series is passed through unchanged, since it is either already
% seasonally adjusted at the source or has no seasonal pattern to remove.
% This function does NOT itself compute any seasonal adjustment -- that
% happens in build_fiscal_sa_levels.py, where the X-13ARIMA-SEATS binary
% runs; this just merges that precomputed result into the data matrix.
%
%   dataM_sa, dataQ_sa   : levels, variables x time -- SA for the 5 fiscal
%                           mnemonics, raw (pass-through) for everything else
%   namesM/Q, groupsM/Q, dates, vintagedate : see load_raw_data()

[dataM, dataQ, namesM, namesQ, groupsM, groupsQ, dates, vintagedate] = load_raw_data();

repo_root = fileparts(fileparts(mfilename('fullpath')));
sa_path = fullfile(repo_root, 'data', 'fiscal_sa_levels.csv');

opts = detectImportOptions(sa_path);
opts = setvartype(opts, opts.VariableNames{1}, 'char');
opts = setvartype(opts, opts.VariableNames(2:end), 'double');
T = readtable(sa_path, opts);

sa_mnemonics = T.Properties.VariableNames(2:end);
sa_data = table2array(T(:, 2:end))';  % variables x time

dataM_sa = f_substitute(dataM, namesM, sa_mnemonics, sa_data);
dataQ_sa = f_substitute(dataQ, namesQ, sa_mnemonics, sa_data);

end


function data_sa = f_substitute(data, names, sa_mnemonics, sa_data)
data_sa = data;
for n = 1 : numel(names)
    sa_idx = find(strcmp(sa_mnemonics, names{n}));
    if ~isempty(sa_idx)
        if numel(data_sa(n, :)) ~= numel(sa_data(sa_idx, :))
            error('load_sa_data: date grid mismatch for %s.', names{n});
        end
        data_sa(n, :) = sa_data(sa_idx, :);
    end
end
end
