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

% Ragged edge: the two series can end on different quarters (e.g. real GDP
% flash already out for a quarter whose deflator isn't yet), so their
% forecast windows start at different quarters (both end at the same
% horizon). Use the union of the two windows and fill each series' quarters
% before its own forecast start with its actual level (identical across
% draws), so nominal GDP covers every quarter either input forecasts.
dates_all = union(dates_real, dates_defl);
levels_real = f_pad_with_actuals(levels_real, dates_real, dates_all, dataQ, namesQ, dates_dt, REAL_VAR);
levels_defl = f_pad_with_actuals(levels_defl, dates_defl, dates_all, dataQ, namesQ, dates_dt, DEFL_VAR);

forecasts_ngdp.dates = dates_all;
forecasts_ngdp.levels_real = levels_real;
forecasts_ngdp.levels_defl = levels_defl;
forecasts_ngdp.levels_nom = levels_real .* levels_defl / 100;

end


function levels_out = f_pad_with_actuals(levels, fc_dates, dates_all, dataQ, namesQ, dates_dt, mnemonic)
% Maps one series' forecast levels (numel(fc_dates) x Ndraws) onto the
% dates_all grid; quarters in dates_all but not in fc_dates must be actual
% observations of the series and are filled with that actual value.
i = find(strcmp(namesQ, mnemonic));
levels_out = NaN(numel(dates_all), size(levels, 2));
[is_fc, loc] = ismember(dates_all, fc_dates);
levels_out(is_fc, :) = levels(loc(is_fc), :);
for h = find(~is_fc(:))'
    idx = find(dates_dt == dates_all(h));
    if isempty(idx) || isnan(dataQ(i, idx))
        error('f_nominal_gdp: %s has neither a forecast nor an actual for %s.', mnemonic, datestr(dates_all(h)));
    end
    levels_out(h, :) = dataQ(i, idx);
end
end
