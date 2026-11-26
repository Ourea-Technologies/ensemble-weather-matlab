% POINTFORECAST A forecast at coordinates and a chosen elevation (needs a Pro key).
%   Reads the key from OUREA_API_KEY; without one it says so and stops.

if strlength(getenv("OUREA_API_KEY")) == 0
    disp("pointForecast: set OUREA_API_KEY to a Pro key to run this example.")
    return
end
client = ensembleweather.Client();
forecast = client.getPointForecast(45.3311, -121.6649, Elevation=2000, MaxHours=48);
if ~isempty(forecast.point)
    p = forecast.point;
    fprintf("Forecast at %g, %g, %g m (%s)\n", p.lat, p.lon, p.elevation, p.elevation_source);
end
for hour = reshape(forecast.series.timeseries, 1, [])
    wind = hour.ensemble.wind_speed;
    fprintf("%s UTC  median wind %g m/s, p90 %g m/s\n", ...
        string(hour.valid_time, "eee HH:mm"), wind.p50, wind.p90);
end
