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
[dataM_sa, dataQ_sa, namesM, namesQ, groupsM, groupsQ, dates, vintagedate] = load_sa_data();
[dataM_stand, dataQ_stand, meansM, meansQ, stdsM, stdsQ, flag_usestartvalsM, flag_usestartvalsQ, dates] = f_growth_rates(dataM_sa, dataQ_sa, namesM, namesQ, dates);

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

% Forecasts: nominal GDP and original unadjusted (NSA) expenditures/revenues
forecasts_ngdp = f_nominal_gdp(draws, dataQ_sa, namesQ, dates_full);
forecasts_nsa = f_reseasonalize(draws, dataQ_raw, dataQ_sa, namesQ, dates_full);

% Plots
dataQ_restand = dataQ_stand .* stdsQ' + meansQ';
dataM_restand = dataM_stand .* stdsM' + meansM';

fiscal_idx_M = find(strcmp(groupsM, 'fiscal'));
fiscal_idx_Q = find(strcmp(groupsQ, 'fiscal'));

fig_fiscal = figure;
tiledlayout(length(fiscal_idx_M) + length(fiscal_idx_Q), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
all_months = round((dates - floor(dates)) * 12) + 1;
for k = 1 : length(fiscal_idx_M)
    i = fiscal_idx_M(k);
    nexttile;
    idx_obs = find(~isnan(dataM_restand(i, :)));
    plot(dates(idx_obs), dataM_restand(i, idx_obs), '-o', 'Color', 'k', ...
         'LineWidth', 1.2, 'MarkerSize', 3);
    title([groupsM{i}, ': ', namesM{i}], 'Interpreter', 'none');
    ylabel('m/m (%)');
    grid on;
    ann_idx = find(all_months == 1 & dates >= dates(idx_obs(1)) & dates <= dates(idx_obs(end)));
    xtick_pos = dates(ann_idx);
    set(gca, 'XTick', xtick_pos, ...
             'XTickLabel', arrayfun(@(d) sprintf('%d', floor(d)), xtick_pos, 'UniformOutput', false), ...
             'XTickLabelRotation', 45);
end
for k = 1 : length(fiscal_idx_Q)
    i = fiscal_idx_Q(k);
    nexttile;
    idx_obs = find(~isnan(dataQ_restand(i, :)));
    plot(dates(idx_obs), dataQ_restand(i, idx_obs), '-o', 'Color', 'k', ...
         'LineWidth', 1.2, 'MarkerSize', 3);
    title([groupsQ{i}, ': ', namesQ{i}], 'Interpreter', 'none');
    ylabel('q/q (%)');
    grid on;
    ann_idx = find(all_months == 1 & dates >= dates(idx_obs(1)) & dates <= dates(idx_obs(end)));
    xtick_pos = dates(ann_idx);
    set(gca, 'XTick', xtick_pos, ...
             'XTickLabel', arrayfun(@(d) sprintf('%dQ1', floor(d)), xtick_pos, 'UniformOutput', false), ...
             'XTickLabelRotation', 45);
end
exportgraphics(fig_fiscal, './output/fiscal_vars.png', 'Resolution', 150);

plot_forecasts(draws, dataQ_restand, dates, options, namesQ, groupsQ, './output', ...
               {'GDP_REAL_Q', 'EXP_GG_TOTAL_Q', 'REV_GG_TOTAL_Q'}, 2022, forecasts_nsa, dataQ_raw, dates_full);