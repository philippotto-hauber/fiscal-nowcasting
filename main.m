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

% data
[~, dataQ_raw, ~, ~, ~, ~, dates_full, ~] = load_raw_data();
[dataM_sa, dataQ_sa, namesM, namesQ, ~, ~, dates, vintagedate] = load_sa_data();

% Nominal GDP, raw EUR level history (full history, pre-drop below --
% already SA at the source per its source_description, so this raw load
% needs no further adjustment). Used only by f_postprocess_draws.m, to
% anchor/history the balance-to-GDP ratio in EUR terms; NOT part of the
% estimated dataset (dropped just below) since GDP_REAL_Q/GDP_DEFLATOR_Q
% already carry the real-GDP/price-level information and f_nominal_gdp.m
% reconstructs an implied nominal GDP index from those two.
ngdp_raw_eur = dataQ_raw(strcmp(namesQ, 'GDP_NOMINAL_Q'), :);

% Drop GDP_NOMINAL_Q from the estimated/forecast dataset -- see above.
idx_drop  = find(strcmp(namesQ, 'GDP_NOMINAL_Q'));
keep      = [1 : idx_drop - 1, idx_drop + 1 : numel(namesQ)];
dataQ_raw = dataQ_raw(keep, :);
dataQ_sa  = dataQ_sa(keep, :);
namesQ    = namesQ(keep);

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

% Forecasts: nominal GDP, GG fiscal balance (% of GDP, history + forecast),
% and original unadjusted (NSA) expenditures/revenues
postproc = f_postprocess_draws(draws, dataQ_sa, namesQ, dates_full, ngdp_raw_eur);
forecasts_nsa = f_reseasonalize(draws, dataQ_raw, dataQ_sa, namesQ, dates_full);

% Plots
dataQ_restand = dataQ_stand .* stdsQ' + meansQ';

plot_gdp_deficit(draws, postproc, dataQ_restand, dates, namesQ, './output', 2022);
write_forecast_summary(draws, postproc, dataQ_restand, dates, namesQ, './output');
plot_annual_balance(postproc, dataQ_sa, namesQ, ngdp_raw_eur, dates_full, './output');