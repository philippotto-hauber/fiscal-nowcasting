function [forecast_dates, levels] = f_cumulate_level(draws, dataQ, namesQ, dates_dt, mnemonic)

% Cumulates a quarterly variable's q/q growth-rate forecast draws onto its
% last actual level, for every draw.
%
%   draws    : must have fields .forecasts_restand (Hq_max x Nq x Ndraws,
%              destandardized q/q growth rate (%) forecasts) and .Hq
%              (1 x Nq, per-variable forecast horizon in quarters) -- both
%              set by GibbsSampler.m. Variable i's forecasts occupy rows
%              Hq_max - Hq(i) + 1 : Hq_max (j=1 earliest, j=Hq_max furthest).
%   dataQ    : levels, variables x time, providing the last actual value to
%              anchor the cumulation to (e.g. dataQ_sa from load_sa_data()).
%   namesQ   : quarterly mnemonics matching dataQ's rows and draws' columns.
%   dates_dt : 1 x T datetime vector matching dataQ's time axis.
%   mnemonic : which variable to cumulate.
%
% Returns:
%   forecast_dates : 1 x Hq_i forecast quarter-end dates (datetime)
%   levels         : Hq_i x Ndraws level forecasts

i = find(strcmp(namesQ, mnemonic));
if isempty(i)
    error('f_cumulate_level: %s not found among quarterly variables.', mnemonic);
end

idx_obs = find(~isnan(dataQ(i, :)));
anchor_level = dataQ(i, idx_obs(end));
anchor_date  = dates_dt(idx_obs(end));

Hq_max  = size(draws.forecasts_restand, 1);
Hq_i    = draws.Hq(i);
j_start = Hq_max - Hq_i + 1;

forecast_dates = anchor_date + calmonths(3 * (1 : Hq_i));

growth_draws = reshape(draws.forecasts_restand(j_start:Hq_max, i, :), Hq_i, []);  % Hq_i x Ndraws
levels = anchor_level * cumprod(1 + growth_draws / 100, 1);

end
