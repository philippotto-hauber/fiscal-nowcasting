function forecasts_ngdp = f_nominal_gdp(draws, dataQ, namesQ, dates)

% Cumulates the model's q/q growth-rate forecasts for real GDP and the GDP
% deflator onto their last actual levels, for every MCMC draw, and combines
% them via the standard national-accounts identity
%   nominal GDP = real GDP x (GDP deflator / 100)
% to produce draws of predicted nominal GDP. Neither GDP_REAL_Q nor
% GDP_DEFLATOR_Q is seasonally adjusted by this pipeline (see
% data/trial_small_monthly_dictionary.json), so no reseasonalization step is
% needed here, unlike f_reseasonalize.m.
%
% Inputs:
%   draws  : must have fields .forecasts_restand (Hq_max x Nq x Ndraws,
%            destandardized q/q growth rate (%) forecasts, as computed in
%            main.m) and .Hq (1 x Nq, per-variable forecast horizon in
%            quarters) -- both set by GibbsSampler.m.
%   dataQ  : quarterly levels, variables x time (e.g. dataQ_sa from
%            load_sa_data(), or dataQ from load_raw_data() -- equivalent for
%            these two variables since neither is seasonally adjusted).
%   namesQ : quarterly mnemonics matching dataQ's rows and draws' columns.
%   dates  : 1 x T, year + (month-1)/12, matching dataQ's time axis.
%
% Returns forecasts_ngdp:
%   .dates       : 1 x Hq forecast quarter-end dates (datetime)
%   .levels_real : Hq x Ndraws real GDP level forecasts (index)
%   .levels_defl : Hq x Ndraws GDP deflator level forecasts (index)
%   .levels_nom  : Hq x Ndraws implied nominal GDP level forecasts (index --
%                  both inputs are index series, not EUR levels, so this is
%                  an implied nominal GDP index, not a EUR amount)

REAL_VAR = 'GDP_REAL_Q';
DEFL_VAR = 'GDP_DEFLATOR_Q';

yr_all = floor(dates);
mo_all = round((dates - yr_all) * 12) + 1;
dates_dt = datetime(yr_all, mo_all, 1);

[dates_real, levels_real] = f_cumulate_level(draws, dataQ, namesQ, dates_dt, REAL_VAR);
[dates_defl, levels_defl] = f_cumulate_level(draws, dataQ, namesQ, dates_dt, DEFL_VAR);

if numel(dates_real) ~= numel(dates_defl) || any(dates_real ~= dates_defl)
    error('f_nominal_gdp: %s and %s do not share the same forecast horizon.', REAL_VAR, DEFL_VAR);
end

forecasts_ngdp.dates = dates_real;
forecasts_ngdp.levels_real = levels_real;
forecasts_ngdp.levels_defl = levels_defl;
forecasts_ngdp.levels_nom = levels_real .* levels_defl / 100;

end
