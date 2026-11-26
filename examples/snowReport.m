% SNOWREPORT A ski-area snow report: season to date, the hourly series as a
%   timetable, and the places with the most new snow nearby.

client = ensembleweather.Client();

season = client.season("or/mt-hood-meadows");
if isempty(season.precipitation)
    disp("season: no precipitation total served yet")
else
    fprintf("water year %d: %g %s of precipitation so far\n", season.water_year, ...
        season.precipitation.amount, season.precipitation.unit);
end

forecast = client.forecast("or/mt-hood-meadows", MaxHours=48);
tt = ensembleweather.toTimetable(forecast);  % one row per hour, one column per quantile
fprintf("%d hours; first median temperature %g\n", height(tt), tt.temperature_p50(1));

ranked = client.explore("snow_5d", State="or", Limit=5);
for item = reshape(ranked.items, 1, [])
    fprintf("%d. %s: %g %s\n", item.rank, item.location.name, item.value, ranked.unit);
end
