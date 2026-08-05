clear all; close all;

addpath("data")
addpath("src")

% options
options.Nburnin = 1000 ; % # of burn-ins
options.Nreplic = 1000 ; % # of replics
options.Nthin = 10 ; % store each options.thinning-th draw
options.Ndisplay = 1000 ;  % display each options.display-th iteration
options.flag_samplemoments = 0;
options.priorswitch = 2; % Normal-Gamma prior

options.Nr = 2 ; % # of static factors
options.Ns = options.Nr ; % # of static factors
options.Np = 3 ; % # of lags in factor VAR
options.Nj = 0 ; % # of lags in eps

% data
[dataM_stand, dataQ_stand, meansM, meansQ, stdsM, stdsQ, flag_usestartvalsM, flag_usestartvalsQ, namesM, namesQ, groupsM, groupsQ, dates, vintagedate] = load_data();

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

% Plots
dataQ_restand = dataQ_stand .* stdsQ' + meansQ';

fiscal_idx = find(strcmp(groupsQ, 'fiscal'));

fig_fiscal = figure;
tiledlayout(length(fiscal_idx), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
all_months = round((dates - floor(dates)) * 12) + 1;
for k = 1 : length(fiscal_idx)
    i = fiscal_idx(k);
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
               {'GDP_REAL_Q', 'EXP_GG_SA_TOTAL_Q', 'REV_GG_SA_TOTAL_Q'}, 2022);