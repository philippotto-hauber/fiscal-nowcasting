function [dataM_stand, dataQ_stand, means, stds, flag_usestartvals, names, groups, dates, vintagedate] = load_data(datapath, samplestart, vintagedate_str)

[dataM_stand, dataQ_stand, means, stds, flag_usestartvals, names, groups, dates, vintagedate] = ...
    f_constructdataset(datapath, samplestart, vintagedate_str, [], [], []);

[dataM_stand, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM_stand, means, stds, names, groups, flag_usestartvals, find(strcmp(names, 'Consumer: Confidence Indicator')));
[dataM_stand, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM_stand, means, stds, names, groups, flag_usestartvals, find(strcmp(names, 'Services: Current level of capacity utilization')));

% --- Bundesbank fiscal data (quarterly) -----------------------------------
% BBGFS1.Q.BQ2180: Einnahmen insgesamt (total revenues)
% BBGFS1.Q.BQ2190: Ausgaben insgesamt (total expenditures)
api_base      = 'https://api.statistiken.bundesbank.de/rest/data/BBGFS1/';
fiscal_series = {'Q.BQ2180', 'Q.BQ2190'};
fiscal_names  = {'total revenues', 'total expenditures'};

Nt           = size(dataM_stand, 2);
dataQ_fiscal = NaN(2, Nt);

for s = 1 : 2
    url      = [api_base, fiscal_series{s}, '?format=csv'];
    tmp_file = [tempdir, 'bbk_fiscal_', num2str(s), '.csv'];
    websave(tmp_file, url);

    % CSV has 10 metadata rows before data rows of the form 'YYYY-QN;value;'
    fid = fopen(tmp_file, 'r', 'n', 'UTF-8');
    for k = 1 : 10; fgetl(fid); end
    raw = textscan(fid, '%s%f%*[^\n]', 'Delimiter', ';');
    fclose(fid);

    dates_str = raw{1};
    values    = raw{2};
    n         = length(values);

    % 'YYYY-QN' -> quarter-start float (Q1->+0, Q2->+0.25, Q3->+0.5, Q4->+0.75)
    dates_q = NaN(1, n);
    for j = 1 : n
        yr         = str2double(dates_str{j}(1:4));
        q          = str2double(dates_str{j}(7));
        dates_q(j) = yr + (q - 1) * 3 / 12;
    end

    % Year-over-year growth rate (4-quarter difference)
    yy        = NaN(1, n);
    yy(5:end) = (values(5:end) - values(1:end-4)) ./ values(1:end-4) * 100;

    % Map onto the sample date grid (tolerance = half a month)
    for j = 1 : n
        idx = find(abs(dates - dates_q(j)) < 1/24, 1);
        if ~isempty(idx)
            dataQ_fiscal(s, idx) = yy(j);
        end
    end
end

% Standardize and append to quarterly dataset
means_fiscal       = NaN(1, 2);
stds_fiscal        = NaN(1, 2);
dataQ_fiscal_stand = NaN(2, Nt);

for s = 1 : 2
    means_fiscal(s)          = mean(dataQ_fiscal(s, :), 'omitnan');
    stds_fiscal(s)           = std(dataQ_fiscal(s, :), 'omitnan');
    dataQ_fiscal_stand(s, :) = (dataQ_fiscal(s, :) - means_fiscal(s)) / stds_fiscal(s);
end

dataQ_stand       = [dataQ_stand;       dataQ_fiscal_stand];
means             = [means,             means_fiscal];
stds              = [stds,              stds_fiscal];
names             = [names,             fiscal_names];
groups            = [groups,            {'fiscal', 'fiscal'}];
flag_usestartvals = [flag_usestartvals, [0, 0]];

end
