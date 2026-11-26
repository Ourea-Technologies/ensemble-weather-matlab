function liveContract()
%LIVECONTRACT A short read-only contract run against the live API (nightly, live.yml).
%   Calls every route once and checks the shapes the toolbox promises. With
%   OUREA_API_KEY set (a read-only Plus or Pro key), the keyed routes run too.
%   It throws on the first failure and prints "live contract: ok" at the end.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

client = ensembleweather.Client(AppUserAgent="ensemble-weather-matlab-live/1");
anonymous = ensembleweather.Client(ApiKey="", AppUserAgent="ensemble-weather-matlab-live/1");
place = "or/mt-hood-meadows";

f = client.forecast(place, MaxHours=48, ...
    Prob=ensembleweather.Chance.atLeast("snowfall", 6, Unit="in"), ...
    Totals=ensembleweather.Total("snowfall", 48));
check(f.location.slug == "mt-hood-meadows", "forecast location");
check(isdatetime(f.series.timeseries(1).valid_time), "valid_time is a datetime");
check(isscalar(f.probabilities) && f.probabilities(1).term == "snowfall:ge:152.40:24h", ...
    "probability term");
check(isscalar(f.window_totals), "window total");
check(height(ensembleweather.toTimetable(f)) == numel(f.series.timeseries), "toTimetable");

plume = anonymous.forecast(place, Members="plume", MaxHours=12, Daily=false);
check(~isempty(plume.series.plume), "plume view");

c = client.current("wa/snoqualmie-pass-i-90");
check(isstruct(c.now) || isempty(c.now), "current conditions");
check(isstruct(client.alerts(place)), "alerts");
check(isstruct(client.nearby(place)), "nearby");

hits = client.search("hood meadows");
check(~isempty(hits.items), "search hits");
sorted = client.search("hood", Sort="snow_5d", Near=[45.33 -121.66]);
check(isstruct(sorted), "search sorted near");

ranked = client.explore("snow_5d", State="or", Limit=5);
check(ranked.metric == "snow_5d", "explore");
pages = client.iterExplore("snow_5d", State="or", Limit=10);
check(numel(pages.collect()) >= numel(ranked.items), "explore iterator");

check(isstruct(client.season(place, IncludeDaily=true)), "season");
check(isstruct(client.snowpack(place)), "snowpack");
check(isstruct(client.snowpackPlume(place)), "snowpack plume");
check(isfield(client.composition(), "models"), "composition");
check(isstruct(client.attribution()), "attribution");
check(isstruct(client.runs(Limit=2)), "runs");
check(isstruct(client.listCatalogLocations(Limit=5)), "catalog locations");
check(isstruct(client.listCatalogStations(Limit=5)), "catalog stations");

outlines = client.alertOutlines(Classes=["winter", "wind"]);
check(outlines.type == "FeatureCollection", "alert outlines");
zones = client.avalancheZones();
check(zones.type == "FeatureCollection", "avalanche zones");
if ~isempty(zones.features)
    check(isfield(zones.features(1).properties, "forecast_url"), "zone keys untouched");
end

try
    anonymous.snowTrend(place);
    error("liveContract:check", "anonymous snow trend should be PLUS_REQUIRED");
catch err
    check(err.identifier == "ensembleweather:permission" && err.Code == "PLUS_REQUIRED", ...
        "anonymous snow trend is PLUS_REQUIRED (" + err.message + ")");
end

if client.HasApiKey
    trend = client.snowTrend(place);
    check(isstruct(trend.grids), "snow trend with a key");
    point = client.getPointForecast(45.3311, -121.6649, Elevation=1661);
    check(~isempty(point.series.timeseries), "point forecast with a key");
else
    disp("live contract: no OUREA_API_KEY, keyed routes skipped")
end
disp("live contract: ok")
end

function check(condition, what)
if ~condition
    error("liveContract:check", "live contract failed: %s", what);
end
end
