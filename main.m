clear all; close all;

addpath("data")
addpath("src")

% set some options
options.Nburnin = 50 ; % # of burn-ins
options.Nreplic = 100 ; % # of replics
options.Nthin = 10 ; % store each options.thinning-th draw
options.Ndisplay = 1000 ;  % display each options.display-th iteration
options.flag_samplemoments = 0;
options.priorswitch = 2; % Normal-Gamma prior
samplestart = 1996 + 1/12 ; 

options.Nr = 8 ; % # of static factors
options.Ns = options.Nr ; % # of static factors
options.Np = 3 ; % # of lags in factor VAR
options.Nj = 0 ; % # of lags in eps

[dataM_stand, dataQ_stand, means, stds, flag_usestartvals, names, groups, dates, vintagedate] = f_constructdataset('./data', samplestart, '2026-05-15', [], [], []);  

[dataM_stand, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM_stand, means, stds, names, groups, flag_usestartvals, find(strcmp(names, 'Consumer: Confidence Indicator')));
[dataM_stand, means, stds, names, groups, flag_usestartvals] = drop_variable(dataM_stand, means, stds, names, groups, flag_usestartvals, find(strcmp(names, 'Services: Current level of capacity utilization')));

% set some more options
options.Nm = size(dataM_stand, 1);
options.Nq = size(dataQ_stand, 1);
options.Nn = options.Nm + options.Nq ; 
options.Nt = size(dataM_stand, 2);
vintagemonth = month(vintagedate) ; 
if ismember(vintagemonth,[3 6 9 12])
    options.Nh = 3 + 6; 
elseif ismember(vintagemonth,[1 4 7 10])
    options.Nh = 2 + 6; 
elseif ismember(vintagemonth,[2 5 8 11])
    options.Nh = 1 + 6;
end

priors = loadpriors(options, options.priorswitch); 

draws = GibbsSampler(dataM_stand, dataQ_stand, priors, options);