% STORMTOTAL Window totals: the distribution of each member's storm total.
%   Never add up hourly quantiles to get a total: the sum of hourly medians
%   is not the median total. Ask the server for the window total instead.

client = ensembleweather.Client();
forecast = client.forecast("or/mt-hood-meadows", Units="imperial", Totals=[
    ensembleweather.Total("snowfall", 72)
    ensembleweather.Total("precipitation", [24 72])
    ]);

for total = reshape(forecast.window_totals, 1, [])
    span = sprintf("%d-%d h", total.start_hours, total.end_hours);
    if isempty(total.quantiles)
        fprintf("%s %s: no distribution (%s)\n", total.variable, span, total.null_reason);
        continue
    end
    q = total.quantiles;
    band = ensembleweather.interval(q);  % [p10 p90], as served
    fprintf("%s %s: median %g in, p10-p90 %g-%g in (%d members)\n", total.variable, span, ...
        q.p50, band(1), band(2), total.members);
end
