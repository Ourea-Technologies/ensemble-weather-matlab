% UNITS The same forecast in metric and imperial units.
%   The server converts; the toolbox never converts response values. Ask
%   for the units you want to show.

client = ensembleweather.Client();
metric = client.forecast("or/mt-hood-meadows");
imperial = client.forecast("or/mt-hood-meadows", Units="imperial");

m = metric.series.timeseries;
i = imperial.series.timeseries;
for k = 1:min(numel(m), numel(i))
    fprintf("%s UTC  median %g °C = %g °F\n", string(m(k).valid_time, "HH:mm"), ...
        m(k).ensemble.temperature.p50, i(k).ensemble.temperature.p50);
end
