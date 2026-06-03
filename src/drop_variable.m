function [dataM, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM, means, stds, names, groups, flag_usestartvals, index_drop)

dataM = [dataM(1 : index_drop - 1, :); ...
    dataM(index_drop + 1 : end, :)];

means = [means(1, 1 : index_drop - 1), ...
    means(1, index_drop + 1 : end)];

stds = [stds(1, 1 : index_drop - 1), ...
    stds(1, index_drop + 1 : end)];

groups = [groups(1, 1 : index_drop - 1), ...
    groups(1, index_drop + 1 : end)];

flag_usestartvals = [flag_usestartvals(1, 1 : index_drop - 1), ...
    flag_usestartvals(1, index_drop + 1 : end)];

names = [names(1, 1 : index_drop - 1), ...
    names(1, index_drop + 1 : end)];
end

