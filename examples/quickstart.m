% QUICKSTART An anonymous forecast for Mt. Hood Meadows, with no API key.
%   Prints each of the next 24 hours' temperature as a range (p10-p90) and
%   the chance of at least 6 in (15 cm) of snow in the next 24 hours.

client = ensembleweather.Client();  % no key: anonymous calls use the Free tier
forecast = client.forecast("or/mt-hood-meadows", Units="imperial", ...
    Prob=ensembleweather.Chance.atLeast("snowfall", 6, Unit="in"));  % the next 24 h

disp(forecast.location.name)
hours = forecast.series.timeseries;
for hour = reshape(hours(1:min(24, end)), 1, [])
    t = hour.ensemble.temperature;
    fprintf("%s UTC  %g to %g °F (p10-p90)\n", ...
        string(hour.valid_time, "eee HH:mm"), t.p10, t.p90);
end

snow = forecast.probabilities(1);
if isempty(snow.value)
    chance = "not available";
else
    chance = sprintf("%.0f%%", 100 * snow.value);
end
fprintf("Chance of at least 6 in of snow in the next 24 h: %s (%d members)\n", ...
    chance, snow.members);
