function [dataM_stand, dataQ_stand, means, stds, flag_usestartvals, names, groups, dates, vintagedate] = load_data(datapath, samplestart, vintagedate_str)

[dataM_stand, dataQ_stand, means, stds, flag_usestartvals, names, groups, dates, vintagedate] = ...
    f_constructdataset(datapath, samplestart, vintagedate_str, [], [], []);

[dataM_stand, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM_stand, means, stds, names, groups, flag_usestartvals, find(strcmp(names, 'Consumer: Confidence Indicator')));
[dataM_stand, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM_stand, means, stds, names, groups, flag_usestartvals, find(strcmp(names, 'Services: Current level of capacity utilization')));

end
