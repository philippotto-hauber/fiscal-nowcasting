function forecasts_nsa = f_reseasonalize(draws, dataQ_raw, dataQ_sa, namesQ, dates)

% Converts the model's seasonally adjusted (SA) quarter-on-quarter growth
% rate forecasts for the two nowcasting targets -- EXP_GG_TOTAL_Q and
% REV_GG_TOTAL_Q -- into forecasts of the original, unadjusted (NSA) levels,
% for every MCMC draw.
%
% Three steps per draw, per target variable:
%   1. Cumulate the SA growth rate draws onto the last actual SA level (from
%      dataQ_sa) to get a path of SA level forecasts.
%   2. For each forecast quarter, look up the seasonal factor implied by
%      raw level / SA level (dataQ_raw vs dataQ_sa) for that calendar
%      quarter, averaged over the most recent N_YEARS of history. X-13
%      itself is not re-run here -- this "forecast factor" approach mirrors
%      how statistical agencies extrapolate seasonal factors ahead of the
%      next concurrent re-estimation (see the "seasonal" R package vignette
%      and Statistics Canada's seasonal adjustment guide).
%   3. Multiply the SA level forecast by that factor to get the NSA level
%      forecast.
%
% Inputs:
%   draws     : must have fields .forecasts_restand (Hq_max x Nq x Ndraws,
%               destandardized q/q SA growth rate (%) forecasts, as computed
%               in main.m) and .Hq (1 x Nq, per-variable forecast horizon in
%               quarters) -- both set by GibbsSampler.m. Variable i's
%               forecasts occupy rows Hq_max - Hq(i) + 1 : Hq_max (j=1
%               earliest, j=Hq_max furthest -- see GibbsSampler.m).
%   dataQ_raw : raw (unadjusted) quarterly levels, variables x time, from
%               load_raw_data() -- full history, NOT the 1996+-truncated
%               version f_growth_rates() produces.
%   dataQ_sa  : seasonally adjusted quarterly levels, variables x time, from
%               load_sa_data() -- same full-history time axis as dataQ_raw.
%   namesQ    : quarterly mnemonics, from load_raw_data()/load_sa_data().
%   dates     : 1 x T, year + (month-1)/12, matching dataQ_raw/dataQ_sa's
%               full-history time axis (i.e. load_raw_data()'s dates output,
%               not f_growth_rates()'s truncated one).
%
% Returns forecasts_nsa, a struct with one field per target mnemonic, each
% containing:
%   .dates      : 1 x Hq_i forecast quarter-end dates (datetime)
%   .factor     : 1 x Hq_i seasonal factors used (raw / SA, by quarter)
%   .levels_sa  : Hq_i x Ndraws seasonally adjusted level forecasts
%   .levels_nsa : Hq_i x Ndraws unadjusted (original-scale) level forecasts

TARGET_VARIABLES = {'EXP_GG_TOTAL_Q', 'REV_GG_TOTAL_Q'};
N_YEARS = 5;  % seasonal factor extrapolation window

yr_all = floor(dates);
mo_all = round((dates - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

forecasts_nsa = struct();
for v = 1 : numel(TARGET_VARIABLES)
    mnemonic = TARGET_VARIABLES{v};
    i = find(strcmp(namesQ, mnemonic));
    if isempty(i)
        error('f_reseasonalize: %s not found among quarterly variables.', mnemonic);
    end

    % --- cumulate SA growth rate draws onto the last actual SA level ---
    [forecast_dates, levels_sa] = f_cumulate_level(draws, dataQ_sa, namesQ, dates_dt, mnemonic);
    Hq_i = numel(forecast_dates);

    % --- seasonal factor per forecast quarter, extrapolated from history ---
    factor = NaN(1, Hq_i);
    for h = 1 : Hq_i
        factor(h) = f_seasonal_factor(dataQ_raw(i, :), dataQ_sa(i, :), dates_dt, ...
                                       month(forecast_dates(h)), N_YEARS);
    end

    % --- reseasonalize ---
    levels_nsa = levels_sa .* factor';

    forecasts_nsa.(mnemonic).dates = forecast_dates;
    forecasts_nsa.(mnemonic).factor = factor;
    forecasts_nsa.(mnemonic).levels_sa = levels_sa;
    forecasts_nsa.(mnemonic).levels_nsa = levels_nsa;
end

end


function factor = f_seasonal_factor(raw_row, sa_row, dates_dt, target_month, n_years)
idx = find(~isnan(raw_row) & ~isnan(sa_row) & month(dates_dt) == target_month);
idx = idx(max(1, end - n_years + 1) : end);
factor = mean(raw_row(idx) ./ sa_row(idx));
end
