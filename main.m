clear all; close all;

addpath("data")
addpath("src")

% options
options.Nburnin = 5000 ; % # of burn-ins
options.Nreplic = 5000 ; % # of replics
options.Nthin = 10 ; % store each options.thinning-th draw
options.Ndisplay = 1000 ;  % display each options.display-th iteration
options.flag_samplemoments = 0;
options.priorswitch = 2; % Normal-Gamma prior

options.Nr = 2 ; % # of static factors
options.Ns = options.Nr ; % # of static factors
options.Np = 3 ; % # of lags in factor VAR
options.Nj = 0 ; % # of lags in eps

% Nominal GDP (raw EUR, NOT EUR millions -- must match the units of
% EXP_GG_TOTAL_Q/REV_GG_TOTAL_Q in dataQ_sa) for the last actual quarter of
% GDP_REAL_Q/GDP_DEFLATOR_Q -- used by f_postprocess_draws.m to rescale its
% implied nominal GDP index onto EUR.
options.anchor_ngdp_eur = 1171696e6 ;

% data
[~, dataQ_raw, ~, ~, ~, ~, dates_full, ~] = load_raw_data();
[dataM_sa, dataQ_sa, namesM, namesQ, ~, ~, dates, vintagedate] = load_sa_data();
[dataM_stand, dataQ_stand, ~, meansQ, ~, stdsQ, flag_usestartvalsM, flag_usestartvalsQ, dates] = f_growth_rates(dataM_sa, dataQ_sa, namesM, namesQ, dates);

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

% MCMC
priors = loadpriors(options, options.priorswitch); 
draws = GibbsSampler(dataM_stand, dataQ_stand, priors, options);

draws.forecasts_restand = draws.forecasts .* reshape(stdsQ, 1, options.Nq, 1) + reshape(meansQ, 1, options.Nq, 1);

% Forecasts: nominal GDP, GG fiscal balance (% of GDP), and original
% unadjusted (NSA) expenditures/revenues
postproc = f_postprocess_draws(draws, dataQ_sa, namesQ, dates_full, options.anchor_ngdp_eur);
forecasts_nsa = f_reseasonalize(draws, dataQ_raw, dataQ_sa, namesQ, dates_full);

% Plots
dataQ_restand = dataQ_stand .* stdsQ' + meansQ';

plot_gdp_deficit(draws, postproc, dataQ_restand, dates, namesQ, './output', 2022);