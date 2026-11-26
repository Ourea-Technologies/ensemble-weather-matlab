function tt = toTimetable(series)
%TOTIMETABLE An hourly series as a timetable of its quantiles.
%   TT = ensembleweather.toTimetable(FORECAST) takes a forecast (the result
%   of Client.forecast or Client.getPointForecast) and returns its hourly
%   series as a timetable: one row per valid_time, and one variable per
%   served quantile of each ensemble quantity, named <quantity>_<stat>
%   (temperature_p10, temperature_p50, snowfall_p90, ...). The wind
%   direction's circular statistics become wind_direction_mean and
%   wind_direction_stddev. A statistic the server did not send is NaN.
%
%   TT = ensembleweather.toTimetable(HOURS) does the same for any struct
%   array of hours (forecast.series.timeseries, or an elevation's hourly).
%
%   The values are the server's, unchanged: nothing is summed or
%   interpolated, so a column of hourly p90s is not a p90 of any total.
%   For window totals, ask the server (ensembleweather.Total).
%
%   Example:
%     forecast = client.forecast("or/mt-hood-meadows", MaxHours=72);
%     tt = ensembleweather.toTimetable(forecast);
%     plot(tt.Time, [tt.temperature_p10 tt.temperature_p50 tt.temperature_p90])
%
%   See also timetable, ensembleweather.Client.forecast.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

if isstruct(series) && isscalar(series) && isfield(series, "series")
    series = series.series;
end
if isstruct(series) && isscalar(series) && isfield(series, "timeseries")
    series = series.timeseries;
end
if ~(isstruct(series) && isfield(series, "valid_time"))
    ensembleweather.internal.usage( ...
        "toTimetable takes a forecast or a struct array of hours (with valid_time)");
end
n = numel(series);
time = datetime(NaN(n, 1), "ConvertFrom", "posixtime", "TimeZone", "UTC", ...
    "Format", ensembleweather.internal.parseTime());
for i = 1:n
    time(i) = series(i).valid_time;
end
names = strings(1, 0);
columns = {};
if isfield(series, "ensemble")
    quantities = {};
    for i = 1:n
        e = series(i).ensemble;
        if isstruct(e)
            quantities = fieldnames(e);
            break
        end
    end
    for q = reshape(string(quantities), 1, [])
        stats = statsOf(series, q);
        for s = stats
            values = NaN(n, 1);
            for i = 1:n
                e = series(i).ensemble;
                if isstruct(e) && isstruct(e.(q)) && isfield(e.(q), s) ...
                        && isnumeric(e.(q).(s)) && isscalar(e.(q).(s))
                    values(i) = e.(q).(s);
                end
            end
            names(end + 1) = q + "_" + s; %#ok<AGROW>
            columns{end + 1} = values; %#ok<AGROW>
        end
    end
end
tt = timetable(time, columns{:}, "VariableNames", names);
tt.Properties.DimensionNames{1} = 'Time';
end

function stats = statsOf(series, quantity)
% The numeric statistics any hour carries for QUANTITY, in a stable order.
order = ["min", "p10", "p25", "p50", "p75", "p90", "max", "mean", "stddev", "probability"];
present = false(size(order));
for i = 1:numel(series)
    e = series(i).ensemble;
    if isstruct(e) && isstruct(e.(quantity))
        q = e.(quantity);
        for k = 1:numel(order)
            if isfield(q, order(k)) && isnumeric(q.(order(k))) && isscalar(q.(order(k)))
                present(k) = true;
            end
        end
    end
end
stats = order(present);
end
