classdef Client < handle
    %CLIENT A client for the Ourea probabilistic weather API (v1).
    %   client = ensembleweather.Client()                     % anonymous (Free tier)
    %   client = ensembleweather.Client(ApiKey="ow_...")      % or set OUREA_API_KEY
    %   client = ensembleweather.Client(Units="imperial", MaxRetries=4)
    %
    %   forecast = client.forecast("or/mt-hood-meadows", Units="imperial", ...
    %       Prob=ensembleweather.Chance.atLeast("snowfall", 6, Unit="in"));
    %   forecast.series.timeseries(1).ensemble.temperature   % p10 ... p90
    %   forecast.probabilities(1).value                      % the chance, 0-1
    %
    %   Every method returns the response as a struct (fields under the
    %   names of the API reference, except the renamed ones listed in the
    %   README) and, as a second output, its metadata:
    %
    %   [forecast, meta] = client.forecast("or/mt-hood-meadows");
    %   meta.rate_limit, meta.request_id, meta.revalidated
    %
    %   Absent or null values are []. Timestamps are UTC datetimes. The
    %   server computes every probability, window total and range from the
    %   full ensemble; the toolbox never sums, averages or interpolates.
    %
    %   Client options (name-value):
    %     ApiKey              - sent as X-API-Key; default: OUREA_API_KEY, else none
    %     BaseUrl             - default: OUREA_BASE_URL, else https://api.oureawx.com
    %     Units               - "metric" (default), "imperial" or "kelvin"
    %     Timeout             - seconds per attempt (default 30)
    %     MaxRetries          - retries after the first attempt (default 2; 0 disables)
    %     Cache               - true (default, a MemoryCache), false, or an ensembleweather.Cache
    %     SendKeyOnOpenRoutes - send the key on the open routes too (default false)
    %     AppUserAgent        - your app's product token, appended to the User-Agent
    %
    %   Open routes (search, catalog detail, attribution, composition) are
    %   sent without the key even when the client has one, so every caller
    %   shares one edge-cache entry; SendKeyOnOpenRoutes=true sends it there
    %   too. Retries: connection errors, 429, 502, 503 and 504, honouring
    %   Retry-After up to 60 s, else full-jitter backoff. Redirects on the
    %   same host keep the key; to any other host they drop it.
    %
    %   Client methods (BEHAVIOR.md 3; the spec's operationId in brackets):
    %     forecast            - a named location's forecast [getLocationForecast]
    %     getPointForecast    - a forecast at coordinates, Pro [getPointForecast]
    %     current             - current conditions [getCurrentConditions]
    %     getPointCurrent     - current conditions at coordinates [getCurrentByCoordinates]
    %     alerts              - active alerts [getLocationAlerts]
    %     getPointAlerts      - active alerts at coordinates [getAlertsByCoordinates]
    %     nearby              - locations near a location [getNearbyLocations]
    %     getPointNearby      - locations near coordinates [getNearbyByCoordinates]
    %     search              - search locations by name [searchLocations]
    %     listLocations       - a page of locations [getAllLocations, getLocations]
    %     listCatalogLocations, catalogLocation - the public catalog
    %     listCatalogStations, catalogStation   - observing stations
    %     runs                - the available model runs [getAvailableRuns]
    %     attribution         - data sources and licences [getAttribution]
    %     explore             - places ranked by a metric [explore]
    %     composition         - the served models and members [getComposition]
    %     season              - season-to-date totals [getLocationSeason]
    %     snowTrend           - each recent run's daily snowfall, Plus [getLocationSnowTrend]
    %     snowpack, snowpackPlume - modelled snowpack, beta
    %     alertOutlines       - alert polygons, GeoJSON [getAlertOutlines]
    %     avalancheZones      - avalanche forecast zones, GeoJSON [getAvalancheZones]
    %     iterLocations, iterCatalogLocations, iterCatalogStations,
    %     iterRuns, iterExplore - lazy iterators (ensembleweather.Pager)
    %
    %   See also ensembleweather.Chance, ensembleweather.Total,
    %   ensembleweather.OureaError, ensembleweather.toTimetable.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Constant)
        Version = "0.1.0"  % the toolbox version
    end

    properties (Constant, Hidden)
        DefaultBaseUrl = "https://api.oureawx.com"
        MaxRedirects = 5
        MaxRetryAfter = 60
        MaxBodyBytes = 64 * 1024 * 1024
    end

    properties (SetAccess = private)
        BaseUrl (1,1) string              % the API's base URL, without a trailing slash
        Units (1,1) string                % the default unit system
        Timeout (1,1) double              % seconds per attempt
        MaxRetries (1,1) double           % retries after the first attempt
        Cache                             % the ETag cache (an ensembleweather.Cache), or []
        SendKeyOnOpenRoutes (1,1) logical % whether open routes carry the key
        UserAgent (1,1) string            % the User-Agent sent
        RateLimit = []                    % the last response's rate-limit state, or []
    end

    properties (Dependent)
        HasApiKey  % whether a key is configured (the key itself is never shown)
    end

    properties (Access = private, Transient)
        KeyFn       % @() the key, so the key never appears in a display of the object
        Transport   % @(request) response
        Sleep       % @(seconds)
        Random      % @() a number in [0, 1)
        Clock       % @() POSIX seconds
    end

    methods
        function obj = Client(options)
            %CLIENT Create a client (see the class help for the options).
            arguments
                options.ApiKey
                options.BaseUrl
                options.Units = "metric"
                options.Timeout = 30
                options.MaxRetries = 2
                options.Cache = true
                options.SendKeyOnOpenRoutes = false
                options.AppUserAgent = ""
                options.Transport
                options.Sleep = @pause
                options.Random = @rand
                options.Clock = @() posixtime(datetime("now", "TimeZone", "UTC"))
            end
            if isfield(options, "ApiKey")
                key = textValue("ApiKey", options.ApiKey, true);
            else
                key = string(getenv("OUREA_API_KEY"));
            end
            obj.KeyFn = @() key;
            if isfield(options, "BaseUrl")
                base = textValue("BaseUrl", options.BaseUrl, false);
            else
                base = string(getenv("OUREA_BASE_URL"));
                if strlength(base) == 0
                    base = ensembleweather.Client.DefaultBaseUrl;
                end
            end
            if ~startsWith(base, ["http://", "https://"])
                ensembleweather.internal.usage("BaseUrl must be an http(s) URL");
            end
            obj.BaseUrl = regexprep(base, "/+$", "");
            obj.Units = unitSystem(options.Units);
            timeout = options.Timeout;
            if ~(isnumeric(timeout) && isscalar(timeout) && isreal(timeout) ...
                    && isfinite(timeout) && timeout > 0)
                ensembleweather.internal.usage("Timeout must be a positive number of seconds");
            end
            obj.Timeout = double(timeout);
            retries = options.MaxRetries;
            if ~(isnumeric(retries) && isscalar(retries) && retries >= 0 ...
                    && retries == fix(retries))
                ensembleweather.internal.usage("MaxRetries must be a whole number, 0 or more");
            end
            obj.MaxRetries = double(retries);
            cache = options.Cache;
            if isa(cache, "ensembleweather.Cache")
                obj.Cache = cache;
            elseif islogical(cache) && isscalar(cache)
                if cache
                    obj.Cache = ensembleweather.MemoryCache();
                else
                    obj.Cache = [];
                end
            elseif isnumeric(cache) && isempty(cache)
                obj.Cache = [];
            else
                ensembleweather.internal.usage( ...
                    "Cache must be true, false or an ensembleweather.Cache");
            end
            obj.SendKeyOnOpenRoutes = logicalValue("SendKeyOnOpenRoutes", ...
                options.SendKeyOnOpenRoutes);
            obj.UserAgent = ensembleweather.internal.userAgent( ...
                textValue("AppUserAgent", options.AppUserAgent, true));
            if isfield(options, "Transport")
                obj.Transport = options.Transport;
            else
                limit = obj.Timeout;
                obj.Transport = @(request) ensembleweather.internal.httpTransport(request, limit);
            end
            obj.Sleep = options.Sleep;
            obj.Random = options.Random;
            obj.Clock = options.Clock;
        end

        function tf = get.HasApiKey(obj)
            tf = strlength(obj.KeyFn()) > 0;
        end

        % --- forecasts ---------------------------------------------------------

        function [result, meta] = forecast(obj, location, options)
            %FORECAST The forecast for a named location [getLocationForecast].
            %   F = client.forecast("or/mt-hood-meadows") or forecast(loc) with a
            %   struct that has state and slug fields (a search hit, say).
            %   Anonymous calls are allowed. Options (name-value; an option you do
            %   not set is not sent):
            %     Prob           - an array of ensembleweather.Chance terms; the
            %                      answers come back in probabilities, in this order
            %     Totals         - an array of ensembleweather.Total requests;
            %                      answers in window_totals, in this order
            %     Units          - "metric", "imperial" or "kelvin" (default: the client's)
            %     MaxHours       - hours of hourly series (6-360; default 24)
            %     IncludePast    - include the hours already past today (default false)
            %     Models         - per-model statistics (default false)
            %     Members        - true, false or "plume" (the plume view in
            %                      series.plume instead of per-hour members)
            %     Elevations     - named elevations, or "all"
            %     Daily, Hourly  - include the daily / hourly series (default true)
            %     MaxDays        - days of daily series (1-15)
            %     Run            - a model run (datetime with a TimeZone, or text)
            %     Sources, ExcludeSources - observation networks to use / skip
            %     Nowcast        - blend recent observations in (default true)
            %     Diagnostics, Include, FeelsLike - extra fields (see the API reference)
            arguments
                obj
                location
                options.Prob
                options.Totals
                options.Units
                options.MaxHours
                options.IncludePast
                options.Models
                options.Members
                options.Elevations
                options.Daily
                options.MaxDays
                options.Hourly
                options.Run
                options.Sources
                options.ExcludeSources
                options.Nowcast
                options.Diagnostics
                options.Include
                options.FeelsLike
            end
            query = ensembleweather.internal.Query();
            query.addList("elevations", opt(options, "Elevations"));
            op = obj.forecastCall("getLocationForecast", locationPath(location), query, options);
            [result, meta] = obj.run(op);
        end

        function [result, meta] = getPointForecast(obj, lat, lon, options)
            %GETPOINTFORECAST The forecast at coordinates (Pro) [getPointForecast].
            %   F = client.getPointForecast(45.3311, -121.6649, Elevation=1661)
            %   Elevation is in metres (default: the terrain's). The other options
            %   are forecast's (except Elevations).
            arguments
                obj
                lat
                lon
                options.Elevation
                options.Prob
                options.Totals
                options.Units
                options.MaxHours
                options.IncludePast
                options.Models
                options.Members
                options.Daily
                options.MaxDays
                options.Hourly
                options.Run
                options.Sources
                options.ExcludeSources
                options.Nowcast
                options.Diagnostics
                options.Include
                options.FeelsLike
            end
            query = coordinates(lat, lon);
            query.add("elevation_m", opt(options, "Elevation"));
            op = obj.forecastCall("getPointForecast", "/api/v1/forecast", query, options);
            [result, meta] = obj.run(op);
        end

        % --- current conditions and alerts --------------------------------------

        function [result, meta] = current(obj, location, options)
            %CURRENT Current conditions at a named location [getCurrentConditions].
            %   C = client.current("wa/snoqualmie-pass-i-90"); C.now.temperature
            %   Options: Units, Sources, ExcludeSources, IncludeNowcastHours (logical).
            %   A mountain pass also carries pass (road status, chances, cameras).
            arguments
                obj
                location
                options.Units
                options.Sources
                options.ExcludeSources
                options.IncludeNowcastHours
            end
            query = ensembleweather.internal.Query();
            [result, meta] = obj.run(obj.currentCall("getCurrentConditions", ...
                locationPath(location) + "/current", query, options));
        end

        function [result, meta] = getPointCurrent(obj, lat, lon, options)
            %GETPOINTCURRENT Current conditions at coordinates [getCurrentByCoordinates].
            %   Options: Elevation (metres), Units, Sources, ExcludeSources,
            %   IncludeNowcastHours.
            arguments
                obj
                lat
                lon
                options.Elevation
                options.Units
                options.Sources
                options.ExcludeSources
                options.IncludeNowcastHours
            end
            query = coordinates(lat, lon);
            query.add("elevation_m", opt(options, "Elevation"));
            options = rmfieldIf(options, "Elevation");
            [result, meta] = obj.run(obj.currentCall("getCurrentByCoordinates", ...
                "/api/v1/current", query, options));
        end

        function [result, meta] = alerts(obj, location)
            %ALERTS Active weather alerts for a named location [getLocationAlerts].
            %   A = client.alerts("or/mt-hood-meadows"); A.count, A.items
            [result, meta] = obj.run(makeCall("getLocationAlerts", ...
                locationPath(location) + "/alerts", ""));
        end

        function [result, meta] = getPointAlerts(obj, lat, lon)
            %GETPOINTALERTS Active weather alerts at coordinates [getAlertsByCoordinates].
            query = coordinates(lat, lon);
            [result, meta] = obj.run(makeCall("getAlertsByCoordinates", ...
                "/api/v1/alerts", query.render()));
        end

        function [result, meta] = alertOutlines(obj, options)
            %ALERTOUTLINES Active alert polygons as GeoJSON [getAlertOutlines].
            %   G = client.alertOutlines(Classes=["winter" "wind"], Bbox=[-125 41 -116 49])
            %   Classes: "wind" and/or "winter". Bbox: [west south east north] in
            %   degrees. The body is a GeoJSON FeatureCollection, passed through
            %   untouched: every key is the API's (no renames), and geometry
            %   coordinates are the raw numbers. jsonencode(rmfield(G, "attribution"))
            %   gives GeoJSON again, for readgeotable or a web map.
            arguments
                obj
                options.Classes
                options.Bbox
            end
            query = ensembleweather.internal.Query();
            query.addList("class", opt(options, "Classes"));
            query.addRaw("bbox", bbox(opt(options, "Bbox")));
            [result, meta] = obj.run(makeCall("getAlertOutlines", ...
                "/api/v1/alerts/outlines", query.render()));
        end

        function [result, meta] = avalancheZones(obj)
            %AVALANCHEZONES Avalanche forecast zones as GeoJSON [getAvalancheZones].
            %   Each feature's properties is the zone's forecast, with the API's
            %   keys (forecast_url, danger_level, ...), passed through untouched.
            [result, meta] = obj.run(makeCall("getAvalancheZones", ...
                "/api/v1/avalanche/zones", ""));
        end

        % --- nearby, search, lists ---------------------------------------------

        function [result, meta] = nearby(obj, location, options)
            %NEARBY Named locations near a named location [getNearbyLocations].
            %   N = client.nearby("or/mt-hood-meadows", Limit=5); N.origin, N.items
            %   Options: Limit (default 3), RadiusKm (default 50), Units.
            arguments
                obj
                location
                options.Limit
                options.RadiusKm
                options.Units
            end
            query = ensembleweather.internal.Query();
            obj.nearbyQuery(query, options);
            [result, meta] = obj.run(makeCall("getNearbyLocations", ...
                locationPath(location) + "/nearby", query.render()));
        end

        function [result, meta] = getPointNearby(obj, lat, lon, options)
            %GETPOINTNEARBY Named locations near coordinates [getNearbyByCoordinates].
            %   Options: Limit (default 3), RadiusKm (default 50), Units.
            arguments
                obj
                lat
                lon
                options.Limit
                options.RadiusKm
                options.Units
            end
            query = coordinates(lat, lon);
            obj.nearbyQuery(query, options);
            [result, meta] = obj.run(makeCall("getNearbyByCoordinates", ...
                "/api/v1/nearby", query.render()));
        end

        function [result, meta] = search(obj, q, options)
            %SEARCH Search named locations [searchLocations] (an open route).
            %   S = client.search("hood meadows"); S.items(1).slug
            %   S = client.search("hood", Sort="snow_5d", Near=[45.33 -121.66])
            %   Options: State, County, Type, Limit (default 20), Sort ("relevance",
            %   the default, or an explore metric: each hit then carries explore),
            %   Order ("desc" or "asc"), Near ([lat lon]), RadiusKm (default 100),
            %   Units. Sent without the key unless SendKeyOnOpenRoutes is set.
            arguments
                obj
                q
                options.State
                options.County
                options.Type
                options.Limit
                options.Sort
                options.Order
                options.Near
                options.RadiusKm
                options.Units
            end
            q = textValue("q", q, false);
            if strlength(strtrim(q)) < 2
                ensembleweather.internal.usage("a search needs at least 2 characters");
            end
            query = ensembleweather.internal.Query();
            query.add("q", q);
            query.add("state", stateCode(opt(options, "State")));
            query.add("county", opt(options, "County"));
            query.add("type", opt(options, "Type"));
            query.add("limit", opt(options, "Limit"), 20);
            query.add("sort", opt(options, "Sort"), "relevance");
            query.add("order", order(opt(options, "Order")), "desc");
            query.addRaw("near", near(opt(options, "Near")));
            query.add("radius_km", opt(options, "RadiusKm"), 100);
            query.add("units", obj.unitsFor(options), "metric");
            [result, meta] = obj.run(makeCall("searchLocations", ...
                "/api/v1/search/locations", query.render(), Open=true));
        end

        function [result, meta] = listLocations(obj, options)
            %LISTLOCATIONS One page of named locations [getAllLocations, getLocations].
            %   P = client.listLocations(State="co", Limit=100); P.items, P.next_cursor
            %   Options: State (omit for every state), Type, Units, Limit, Cursor.
            %   See also iterLocations.
            arguments
                obj
                options.State
                options.Type
                options.Units
                options.Limit
                options.Cursor
            end
            query = ensembleweather.internal.Query();
            query.add("type", opt(options, "Type"));
            query.add("units", obj.unitsFor(options), "metric");
            state = opt(options, "State");
            if isempty(state)
                query.add("limit", opt(options, "Limit"), 500);
                query.add("cursor", opt(options, "Cursor"));
                op = makeCall("getAllLocations", "/api/v1/locations", query.render());
            else
                query.add("limit", opt(options, "Limit"));
                query.add("cursor", opt(options, "Cursor"));
                op = makeCall("getLocations", "/api/v1/locations/" ...
                    + ensembleweather.internal.encode(stateCode(state)), query.render());
            end
            [result, meta] = obj.run(op);
        end

        function pager = iterLocations(obj, options)
            %ITERLOCATIONS Every named location, lazily (an ensembleweather.Pager).
            %   Takes listLocations' options except Cursor.
            arguments
                obj
                options.State
                options.Type
                options.Units
                options.Limit
            end
            pager = makePager(@(varargin) obj.listLocations(varargin{:}), {}, options);
        end

        function [result, meta] = listCatalogLocations(obj, options)
            %LISTCATALOGLOCATIONS One page of the public location catalog [listCatalogLocations].
            %   Options: Admin1, Country, Type, Template, Limit (default 20), Cursor.
            %   This list keeps the key (keyed callers get their own budget).
            arguments
                obj
                options.Admin1
                options.Country
                options.Type
                options.Template
                options.Limit
                options.Cursor
            end
            query = ensembleweather.internal.Query();
            query.add("admin1", opt(options, "Admin1"));
            query.add("country", opt(options, "Country"));
            query.add("type", opt(options, "Type"));
            query.add("template", opt(options, "Template"));
            query.add("limit", opt(options, "Limit"), 20);
            query.add("cursor", opt(options, "Cursor"));
            [result, meta] = obj.run(makeCall("listCatalogLocations", ...
                "/api/v1/catalog/locations", query.render()));
        end

        function pager = iterCatalogLocations(obj, options)
            %ITERCATALOGLOCATIONS The whole location catalog, lazily (an ensembleweather.Pager).
            arguments
                obj
                options.Admin1
                options.Country
                options.Type
                options.Template
                options.Limit
            end
            pager = makePager(@(varargin) obj.listCatalogLocations(varargin{:}), {}, options);
        end

        function [result, meta] = catalogLocation(obj, slug, options)
            %CATALOGLOCATION One catalog location's detail [getCatalogLocation] (open route).
            %   Options: Include (for example ["content" "template"]), Locale (default "en").
            arguments
                obj
                slug
                options.Include
                options.Locale
            end
            query = ensembleweather.internal.Query();
            query.addList("include", opt(options, "Include"));
            query.add("locale", opt(options, "Locale"), "en");
            [result, meta] = obj.run(makeCall("getCatalogLocation", ...
                "/api/v1/catalog/locations/" ...
                + ensembleweather.internal.encode(textValue("slug", slug, false)), ...
                query.render(), Open=true));
        end

        function [result, meta] = listCatalogStations(obj, options)
            %LISTCATALOGSTATIONS One page of the station catalog [listCatalogStations].
            %   Options: Admin1, Country, Network, Capabilities, Status,
            %   Limit (default 20), Cursor. Keeps the key.
            arguments
                obj
                options.Admin1
                options.Country
                options.Network
                options.Capabilities
                options.Status
                options.Limit
                options.Cursor
            end
            query = ensembleweather.internal.Query();
            query.add("admin1", opt(options, "Admin1"));
            query.add("country", opt(options, "Country"));
            query.addList("network", opt(options, "Network"));
            query.addList("capability", opt(options, "Capabilities"));
            query.add("status", opt(options, "Status"));
            query.add("limit", opt(options, "Limit"), 20);
            query.add("cursor", opt(options, "Cursor"));
            [result, meta] = obj.run(makeCall("listCatalogStations", ...
                "/api/v1/catalog/stations", query.render()));
        end

        function pager = iterCatalogStations(obj, options)
            %ITERCATALOGSTATIONS The whole station catalog, lazily (an ensembleweather.Pager).
            arguments
                obj
                options.Admin1
                options.Country
                options.Network
                options.Capabilities
                options.Status
                options.Limit
            end
            pager = makePager(@(varargin) obj.listCatalogStations(varargin{:}), {}, options);
        end

        function [result, meta] = catalogStation(obj, slug, options)
            %CATALOGSTATION One station's detail [getCatalogStation] (open route).
            %   Options: Include, Locale (default "en").
            arguments
                obj
                slug
                options.Include
                options.Locale
            end
            query = ensembleweather.internal.Query();
            query.addList("include", opt(options, "Include"));
            query.add("locale", opt(options, "Locale"), "en");
            [result, meta] = obj.run(makeCall("getCatalogStation", ...
                "/api/v1/catalog/stations/" ...
                + ensembleweather.internal.encode(textValue("slug", slug, false)), ...
                query.render(), Open=true));
        end

        function [result, meta] = runs(obj, options)
            %RUNS The model runs available to forecast from [getAvailableRuns].
            %   Options: Limit (default 10), Cursor.
            arguments
                obj
                options.Limit
                options.Cursor
            end
            query = ensembleweather.internal.Query();
            query.add("limit", opt(options, "Limit"), 10);
            query.add("cursor", opt(options, "Cursor"));
            [result, meta] = obj.run(makeCall("getAvailableRuns", "/api/v1/runs", ...
                query.render()));
        end

        function pager = iterRuns(obj, options)
            %ITERRUNS Every available model run, lazily (an ensembleweather.Pager).
            arguments
                obj
                options.Limit
            end
            pager = makePager(@(varargin) obj.runs(varargin{:}), {}, options);
        end

        function [result, meta] = attribution(obj)
            %ATTRIBUTION The data providers, licences and notices [getAttribution] (open route).
            [result, meta] = obj.run(makeCall("getAttribution", "/api/v1/attribution", "", ...
                Open=true));
        end

        function [result, meta] = composition(obj)
            %COMPOSITION The served models and their members [getComposition] (open route).
            [result, meta] = obj.run(makeCall("getComposition", "/api/v1/composition", "", ...
                Open=true));
        end

        % --- explore, season, snow -----------------------------------------------

        function [result, meta] = explore(obj, metric, options)
            %EXPLORE One page of places ranked by a metric [explore].
            %   E = client.explore("snow_5d", State="or", Near=[45.33 -121.66], RadiusKm=50)
            %   Metrics: base_depth new_snow_24h snow_today snow_5d snow_10d snow_14d
            %   precip_today precip_5d precip_10d precip_14d season_precip
            %   season_precip_pct_normal season_snow. Options: Order ("desc", the
            %   default, or "asc"), Type, State, Near ([lat lon]), RadiusKm (default
            %   100), ElevationMin, ElevationMax, Points ("primary", the default, or
            %   "all"), Limit (default 25), Cursor, Units. See also iterExplore.
            arguments
                obj
                metric
                options.Order
                options.Type
                options.State
                options.Near
                options.RadiusKm
                options.ElevationMin
                options.ElevationMax
                options.Points
                options.Limit
                options.Cursor
                options.Units
            end
            query = ensembleweather.internal.Query();
            query.add("metric", textValue("metric", metric, false));
            query.add("order", order(opt(options, "Order")), "desc");
            query.add("type", opt(options, "Type"));
            query.add("state", stateCode(opt(options, "State")));
            query.addRaw("near", near(opt(options, "Near")));
            query.add("radius_km", opt(options, "RadiusKm"), 100);
            query.add("elevation_min", opt(options, "ElevationMin"));
            query.add("elevation_max", opt(options, "ElevationMax"));
            points = opt(options, "Points");
            if ~isempty(points) && ~any(string(points) == ["primary", "all"])
                ensembleweather.internal.usage("Points must be ""primary"" or ""all""");
            end
            query.add("points", points, "primary");
            query.add("limit", opt(options, "Limit"), 25);
            query.add("cursor", opt(options, "Cursor"));
            query.add("units", obj.unitsFor(options), "metric");
            [result, meta] = obj.run(makeCall("explore", "/api/v1/explore", query.render()));
        end

        function pager = iterExplore(obj, metric, options)
            %ITEREXPLORE Every place ranked by METRIC, lazily (an ensembleweather.Pager).
            %   Takes explore's options except Cursor.
            arguments
                obj
                metric
                options.Order
                options.Type
                options.State
                options.Near
                options.RadiusKm
                options.ElevationMin
                options.ElevationMax
                options.Points
                options.Limit
                options.Units
            end
            pager = makePager(@(varargin) obj.explore(varargin{:}), {metric}, options);
        end

        function [result, meta] = season(obj, location, options)
            %SEASON Observed season-to-date precipitation and snowfall [getLocationSeason].
            %   S = client.season("or/mt-hood-meadows", IncludeDaily=true)
            %   Options: WaterYear (2027 or later; default the current one),
            %   IncludeDaily (logical), Units.
            arguments
                obj
                location
                options.WaterYear
                options.IncludeDaily
                options.Units
            end
            query = ensembleweather.internal.Query();
            query.add("water_year", opt(options, "WaterYear"));
            daily = flag(options, "IncludeDaily");
            if ~isempty(daily) && daily
                query.addList("include", "daily");
            end
            query.add("units", obj.unitsFor(options), "metric");
            [result, meta] = obj.run(makeCall("getLocationSeason", ...
                locationPath(location) + "/season", query.render()));
        end

        function [result, meta] = snowTrend(obj, location, options)
            %SNOWTREND Each recent model run's daily snowfall [getLocationSnowTrend].
            %   Plus or Pro: anonymous and Free callers get an
            %   ensembleweather:permission error with Code PLUS_REQUIRED.
            %   Options: Elevation (a named elevation, e.g. "main_lodge"), Units.
            arguments
                obj
                location
                options.Elevation
                options.Units
            end
            query = ensembleweather.internal.Query();
            query.add("elevation", opt(options, "Elevation"));
            query.add("units", obj.unitsFor(options), "metric");
            [result, meta] = obj.run(makeCall("getLocationSnowTrend", ...
                locationPath(location) + "/snow-trend", query.render()));
        end

        function [result, meta] = snowpack(obj, location, options)
            %SNOWPACK The modelled snowpack at a location (beta) [getLocationSnowpack].
            %   The body carries beta = true. definitions.surface and
            %   definitions.layer_form are dictionaries (code -> text).
            arguments
                obj
                location
                options.Units
            end
            query = ensembleweather.internal.Query();
            query.add("units", obj.unitsFor(options), "metric");
            [result, meta] = obj.run(makeCall("getLocationSnowpack", ...
                locationPath(location) + "/snowpack", query.render()));
        end

        function [result, meta] = snowpackPlume(obj, location, options)
            %SNOWPACKPLUME The snowpack depth plume across models (beta) [getLocationSnowpackPlume].
            arguments
                obj
                location
                options.Units
            end
            query = ensembleweather.internal.Query();
            query.add("units", obj.unitsFor(options), "metric");
            [result, meta] = obj.run(makeCall("getLocationSnowpackPlume", ...
                locationPath(location) + "/snowpack/plume", query.render()));
        end
    end

    % --- internals ------------------------------------------------------------------

    methods (Access = private)
        function units = unitsFor(obj, options)
            if isfield(options, "Units")
                units = unitSystem(options.Units);
            else
                units = obj.Units;
            end
        end

        function nearbyQuery(obj, query, options)
            query.add("limit", opt(options, "Limit"), 3);
            query.add("radius_km", opt(options, "RadiusKm"), 50);
            query.add("units", obj.unitsFor(options), "metric");
        end

        function op = currentCall(obj, operation, path, query, options)
            query.add("units", obj.unitsFor(options), "metric");
            query.addList("sources", opt(options, "Sources"));
            query.addList("exclude_sources", opt(options, "ExcludeSources"));
            nowcastHours = flag(options, "IncludeNowcastHours");
            if ~isempty(nowcastHours) && nowcastHours
                query.add("include", "nowcast_hours");
            end
            op = makeCall(operation, path, query.render());
        end

        function op = forecastCall(obj, operation, path, query, options)
            system = obj.unitsFor(options);
            query.add("units", system, "metric");
            query.add("max_hours", opt(options, "MaxHours"), 24);
            query.add("include_past", flag(options, "IncludePast"), false);
            query.add("models", flag(options, "Models"), false);
            query.add("members", members(opt(options, "Members")), false);
            query.add("daily", flag(options, "Daily"), true);
            query.add("max_days", opt(options, "MaxDays"));
            query.add("hourly", flag(options, "Hourly"), true);
            query.add("run", opt(options, "Run"));
            query.addList("sources", opt(options, "Sources"));
            query.addList("exclude_sources", opt(options, "ExcludeSources"));
            query.add("nowcast", flag(options, "Nowcast"), true);
            query.addList("diagnostics", opt(options, "Diagnostics"));
            query.addList("include", opt(options, "Include"));
            feels = opt(options, "FeelsLike");
            if ~isempty(feels) && ~isequal(unique(string(feels)), "nws")
                query.addList("feels_like", feels);
            end
            chances = items(opt(options, "Prob"), "ensembleweather.Chance", "Prob");
            totals = items(opt(options, "Totals"), "ensembleweather.Total", "Totals");
            [probWire, chanceTerms] = ensembleweather.internal.probQuery(chances, system);
            [totalsWire, totalTerms] = totalsQuery(totals);
            query.addRaw("prob", probWire);
            query.addRaw("totals", totalsWire);
            finish = [];
            if ~isempty(chances) || ~isempty(totals)
                finish = @(result) answerInOrder(result, operation, chanceTerms, totalTerms);
            end
            op = makeCall(operation, path, query.render(), Finish=finish);
        end

        function [result, meta] = run(obj, op)
            % Send OP: credentials, cache, redirects, retries, decoding.
            url = obj.BaseUrl + op.path;
            if strlength(op.query) > 0
                url = url + "?" + op.query;
            end
            key = obj.KeyFn();
            headers = ["User-Agent", obj.UserAgent; "Accept", "application/json"];
            sendKey = strlength(key) > 0 && (~op.open || obj.SendKeyOnOpenRoutes);
            if sendKey
                headers(end + 1, :) = ["X-API-Key", key];
            end
            cacheKey = "";
            cached = [];
            if ~isempty(obj.Cache)
                identity = "anonymous";
                if sendKey
                    identity = extractBefore(ensembleweather.internal.sha256(key), 33);
                end
                cacheKey = url + " " + identity;
                cached = obj.Cache.get(cacheKey);
                if ~isempty(cached)
                    if cached.maxAge > 0 && obj.Clock() - cached.storedAt < cached.maxAge
                        [result, meta] = obj.decodeBody(op, url, 200, cached.headers, ...
                            cached.body, false, true);
                        return
                    end
                    if strlength(cached.etag) > 0
                        headers(end + 1, :) = ["If-None-Match", cached.etag];
                    end
                end
            end
            attempt = 1;
            while true
                try
                    response = obj.send(url, headers);
                catch failure
                    if isa(failure, "ensembleweather.OureaError")
                        rethrow(failure);
                    end
                    if ~isTlsFailure(failure) && attempt <= obj.MaxRetries
                        obj.Sleep(obj.jitter(attempt));
                        attempt = attempt + 1;
                        continue
                    end
                    throw(ensembleweather.OureaError("connection", ...
                        obj.scrub(string(failure.identifier) + ": " + failure.message)));
                end
                status = response.status;
                responseHeaders = response.headers;
                obj.RateLimit = ensembleweather.internal.rateLimit(responseHeaders);
                ensembleweather.internal.deprecation("check", op.operation, responseHeaders);
                if status == 304 && ~isempty(cached)
                    entry = obj.revalidate(cacheKey, cached, responseHeaders);
                    [result, meta] = obj.decodeBody(op, url, 304, entry.headers, ...
                        entry.body, true, true);
                    return
                end
                body = bodyText(response.body);
                if status >= 200 && status < 300
                    obj.store(cacheKey, responseHeaders, body);
                    [result, meta] = obj.decodeBody(op, url, status, responseHeaders, ...
                        body, false, false);
                    return
                end
                failure = obj.apiError(status, responseHeaders, body);
                if any(status == [429 502 503 504]) && attempt <= obj.MaxRetries
                    wait = [];
                    if any(status == [429 503 504])
                        wait = failure.RetryAfter;
                    end
                    if isempty(wait)
                        wait = obj.jitter(attempt);
                    elseif wait > ensembleweather.Client.MaxRetryAfter
                        throw(failure);
                    end
                    obj.Sleep(wait);
                    attempt = attempt + 1;
                    continue
                end
                throw(failure);
            end
        end

        function response = send(obj, url, headers)
            % One attempt: GET, following same-host and cross-host redirects.
            current = url;
            sent = headers;
            for hop = 0:ensembleweather.Client.MaxRedirects
                response = obj.Transport(struct("method", "GET", "url", current, "headers", sent));
                if numel(response.body) > ensembleweather.Client.MaxBodyBytes
                    throw(ensembleweather.OureaError("unexpected_response", ...
                        "the response body is larger than 64 MiB"));
                end
                location = ensembleweather.internal.header(response.headers, "Location");
                if ~any(response.status == [301 302 307 308]) || isempty(location) ...
                        || hop == ensembleweather.Client.MaxRedirects
                    return
                end
                current = resolveUrl(current, location);
                sent = headers;
                if ~sameOrigin(current, obj.BaseUrl)
                    drop = ismember(lower(sent(:, 1)), ["x-api-key", "if-none-match"]);
                    sent = sent(~drop, :);
                end
            end
        end

        function delay = jitter(obj, attempt)
            delay = obj.Random() * min(8, 0.5 * 2^(attempt - 1));
        end

        function store(obj, cacheKey, headers, body)
            if isempty(obj.Cache) || strlength(cacheKey) == 0
                return
            end
            etag = ensembleweather.internal.header(headers, "ETag");
            maxAge = maxAgeOf(headers);
            if hasDirective(headers, "no-store") || (isempty(etag) && ~(maxAge > 0))
                obj.Cache.remove(cacheKey);
                return
            end
            if isempty(etag)
                etag = "";
            end
            obj.Cache.set(cacheKey, struct("body", body, "etag", etag, ...
                "headers", headers, "storedAt", obj.Clock(), "maxAge", maxAge));
        end

        function entry = revalidate(obj, cacheKey, cached, headers)
            % A 304: keep the stored body, take the fresh headers.
            merged = cached.headers;
            for i = 1:size(headers, 1)
                same = strcmpi(merged(:, 1), headers(i, 1));
                merged = [merged(~same, :); headers(i, :)];
            end
            entry = cached;
            etag = ensembleweather.internal.header(headers, "ETag");
            if ~isempty(etag)
                entry.etag = etag;
            end
            entry.headers = merged;
            entry.storedAt = obj.Clock();
            entry.maxAge = maxAgeOf(headers);
            if hasDirective(headers, "no-store")
                obj.Cache.remove(cacheKey);
            else
                obj.Cache.set(cacheKey, entry);
            end
        end

        function [result, meta] = decodeBody(obj, op, url, status, headers, body, ...
                revalidated, fromCache)
            try
                data = jsondecode(body);
            catch failure
                throw(ensembleweather.OureaError("unexpected_response", op.operation ...
                    + ": the response is not JSON (" + failure.message + ")"));
            end
            try
                result = ensembleweather.internal.decode(data, op.type, op.geojson);
            catch failure
                if failure.identifier ~= "ensembleweather:internal:decode"
                    rethrow(failure);
                end
                throw(ensembleweather.OureaError("unexpected_response", op.operation ...
                    + ": the response is not the documented " + extractAfter(op.type, 2) ...
                    + " (" + failure.message + ")"));
            end
            if ~isempty(op.finish)
                result = op.finish(result);
            end
            meta = struct( ...
                "status", status, ...
                "url", url, ...
                "headers", headers, ...
                "request_id", {ensembleweather.internal.header(headers, "X-Request-Id")}, ...
                "rate_limit", {ensembleweather.internal.rateLimit(headers)}, ...
                "etag", {ensembleweather.internal.header(headers, "ETag")}, ...
                "revalidated", revalidated, ...
                "from_cache", fromCache);
        end

        function failure = apiError(obj, status, headers, body)
            % The error for a non-2xx response (BEHAVIOR.md 8).
            code = [];
            message = "HTTP " + status;
            details = struct();
            data = [];
            try
                data = jsondecode(body);
            catch
            end
            if isstruct(data) && isscalar(data) && isfield(data, "error") && ischar(data.error)
                code = string(data.error);
                if isfield(data, "message") && ischar(data.message)
                    message = string(data.message);
                end
                for pair = ["request_id", "RequestId"; "doc_url", "DocUrl"; "param", "Param"]'
                    if isfield(data, pair(1)) && ischar(data.(pair(1)))
                        details.(pair(2)) = obj.scrub(string(data.(pair(1))));
                    end
                end
                if isfield(data, "nearest_location") && isstruct(data.nearest_location)
                    details.NearestLocation = data.nearest_location;
                end
            elseif strlength(body) > 0
                snippet = strtrim(extractBefore(body, min(strlength(body), 200) + 1));
                if strlength(snippet) > 0
                    message = "HTTP " + status + ": " + snippet;
                end
            end
            if ~isfield(details, "RequestId")
                requestId = ensembleweather.internal.header(headers, "X-Request-Id");
                if ~isempty(requestId)
                    details.RequestId = requestId;
                end
            end
            details.Status = status;
            details.Code = code;
            details.RetryAfter = ensembleweather.internal.retryAfter( ...
                ensembleweather.internal.header(headers, "Retry-After"), obj.Clock());
            details.RateLimit = ensembleweather.internal.rateLimit(headers);
            label = string(status);
            if ~isempty(code)
                label = label + " " + code;
            end
            text = label + ": " + message;
            if isfield(details, "RequestId")
                text = text + " (request id " + details.RequestId + ")";
            end
            failure = ensembleweather.OureaError(errorCategory(status, code), ...
                obj.scrub(text), details);
        end

        function text = scrub(obj, text)
            key = obj.KeyFn();
            if strlength(key) > 0
                text = replace(text, key, "[redacted]");
            end
        end
    end
end

% --- local functions -------------------------------------------------------------------

function op = makeCall(operation, path, query, options)
% One operation, ready to send: its route, canonical query and response type.
arguments
    operation (1,1) string
    path (1,1) string
    query (1,1) string
    options.Open (1,1) logical = false
    options.Finish = []
end
table = ensembleweather.internal.schemaTable();
spec = table.Operations(char(operation));
op = struct("operation", operation, "path", path, "query", query, ...
    "open", options.Open, "type", spec.type, "geojson", spec.geojson, ...
    "finish", {options.Finish});
end

function pager = makePager(method, leading, options)
% A Pager over METHOD(LEADING{:}, OPTIONS..., Cursor=cursor).
args = namedargs2cell(options);
pager = ensembleweather.Pager(@(cursor) fetchPage(method, leading, args, cursor));
end

function page = fetchPage(method, leading, args, cursor)
if isempty(cursor)
    page = method(leading{:}, args{:});
else
    page = method(leading{:}, args{:}, "Cursor", cursor);
end
end

function value = opt(options, name)
% A name-value option, or [] when the caller did not set it.
if isfield(options, name)
    value = options.(name);
else
    value = [];
end
end

function options = rmfieldIf(options, name)
if isfield(options, name)
    options = rmfield(options, name);
end
end

function value = flag(options, name)
% A logical option (true/false, or 1/0), or [] when not set.
value = opt(options, name);
if isempty(value)
    return
end
value = logicalValue(name, value);
end

function value = logicalValue(name, value)
if isnumeric(value) && isscalar(value) && any(value == [0 1])
    value = logical(value);
end
if ~(islogical(value) && isscalar(value))
    ensembleweather.internal.usage("%s must be true or false", name);
end
end

function value = textValue(name, value, allowEmpty)
if ischar(value) && (isrow(value) || isempty(value))
    value = string(value);
end
if ~(isstring(value) && isscalar(value) && ~ismissing(value))
    ensembleweather.internal.usage("%s must be text", name);
end
if ~allowEmpty && strlength(value) == 0
    ensembleweather.internal.usage("%s must not be empty", name);
end
end

function units = unitSystem(value)
units = textValue("Units", value, false);
if ~any(units == ["metric", "imperial", "kelvin"])
    ensembleweather.internal.usage("Units must be ""metric"", ""imperial"" or ""kelvin"", not ""%s""", ...
        units);
end
end

function value = members(value)
% Members: true, false or "plume".
if isempty(value)
    return
end
if isnumeric(value) && isscalar(value) && any(value == [0 1])
    value = logical(value);
end
if islogical(value) && isscalar(value)
    return
end
if (ischar(value) || isstring(value)) && string(value) == "plume"
    value = "plume";
    return
end
ensembleweather.internal.usage("Members takes true, false or ""plume""");
end

function value = order(value)
if ~isempty(value) && ~any(string(value) == ["asc", "desc"])
    ensembleweather.internal.usage("Order must be ""asc"" or ""desc""");
end
end

function code = stateCode(state)
% Lowercase a two-letter USPS code; pass anything else (a state name) through.
code = state;
if isempty(state)
    return
end
code = textValue("state", state, false);
if strlength(code) == 2 && all(isletter(char(code)))
    code = lower(code);
end
end

function path = locationPath(location)
% /api/v1/locations/{state}/{slug}, each segment percent-encoded.
if isstruct(location) && isscalar(location) && isfield(location, "state") ...
        && isfield(location, "slug")
    state = location.state;
    slug = location.slug;
    if isempty(slug)
        ensembleweather.internal.usage("this location has no slug (a coordinate forecast's)");
    end
else
    text = textValue("location", location, false);
    parts = split(text, "/");
    if numel(parts) ~= 2
        ensembleweather.internal.usage( ...
            "a location is ""state/slug"" (for example ""or/mt-hood-meadows""), got ""%s""", text);
    end
    state = parts(1);
    slug = parts(2);
end
path = "/api/v1/locations/" + ensembleweather.internal.encode(stateCode(state)) + "/" ...
    + ensembleweather.internal.encode(textValue("slug", slug, false));
end

function query = coordinates(lat, lon)
query = ensembleweather.internal.Query();
query.addRaw("lat", degrees("lat", lat, 90));
query.addRaw("lon", degrees("lon", lon, 180));
end

function text = degrees(name, value, bound)
if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value))
    ensembleweather.internal.usage("%s must be a finite number", name);
end
if value < -bound || value > bound
    ensembleweather.internal.usage("%s must be within +/-%d, got %g", name, bound, value);
end
text = ensembleweather.internal.formatNumber(value);
end

function text = near(value)
% [lat lon] as "lat,lon" with a literal comma, or "" when unset.
text = "";
if isempty(value)
    return
end
if ~(isnumeric(value) && numel(value) == 2)
    ensembleweather.internal.usage("Near is [lat lon] in degrees");
end
text = degrees("Near latitude", value(1), 90) + "," + degrees("Near longitude", value(2), 180);
end

function text = bbox(value)
% [west south east north] as "west,south,east,north", or "" when unset.
text = "";
if isempty(value)
    return
end
if ~(isnumeric(value) && numel(value) == 4)
    ensembleweather.internal.usage("Bbox is [west south east north] in degrees");
end
if value(1) > value(3) || value(2) > value(4)
    ensembleweather.internal.usage( ...
        "a Bbox is [west south east north] with west <= east and south <= north");
end
text = join([degrees("west", value(1), 180), degrees("south", value(2), 90), ...
    degrees("east", value(3), 180), degrees("north", value(4), 90)], ",");
end

function list = items(value, className, name)
% An array of CLASSNAME objects from an array or a cell array of them.
if isempty(value)
    list = [];
    return
end
if iscell(value)
    if ~all(cellfun(@(v) isa(v, className), value))
        ensembleweather.internal.usage("%s takes %s objects", name, className);
    end
    list = [value{:}];
elseif isa(value, className)
    list = reshape(value, 1, []);
else
    ensembleweather.internal.usage("%s takes %s objects", name, className);
end
end

function [wire, terms] = totalsQuery(totals)
% The canonical totals= value (sorted by variable then window) and each request's term.
terms = strings(1, numel(totals));
keys = zeros(numel(totals), 3);
for i = 1:numel(totals)
    terms(i) = totals(i).wire();
    keys(i, :) = [double(totals(i).Variable == "snowfall"), totals(i).Window];
end
if isempty(terms)
    wire = "";
    return
end
[~, first] = unique(terms, "stable");
[~, ranks] = sortrows(keys(first, :));
wire = join(terms(first(ranks)), ",");
end

function result = answerInOrder(result, operation, chanceTerms, totalTerms)
% Match answers to the caller's terms by the echoed term, never by position.
if ~isempty(chanceTerms) && ~isempty(result.probabilities)
    result.probabilities = byTerm(result.probabilities, chanceTerms, operation);
end
if ~isempty(totalTerms) && ~isempty(result.window_totals)
    result.window_totals = byTerm(result.window_totals, totalTerms, operation);
end
end

function ordered = byTerm(answers, terms, operation)
sent = [answers.term];
index = zeros(numel(terms), 1);
for i = 1:numel(terms)
    found = find(sent == terms(i), 1);
    if isempty(found)
        throw(ensembleweather.OureaError("unexpected_response", ...
            operation + ": the response has no answer for " + terms(i)));
    end
    index(i) = found;
end
ordered = answers(index);
end

function category = errorCategory(status, code)
% By code first, then by status (BEHAVIOR.md 8).
byCode = dictionary( ...
    ["INVALID_API_KEY", "UNAUTHORIZED", "PRO_REQUIRED", "PLUS_REQUIRED", ...
    "LOCATION_NOT_FOUND", "NOT_FOUND", "BAD_REQUEST", "INVALID_COORDINATES", ...
    "INVALID_ELEVATION", "ELEVATION_REQUIRED", "OUTSIDE_COVERAGE", "TOO_MANY_REQUESTS", ...
    "FORECAST_UNAVAILABLE", "TIMEOUT", "INTERNAL_ERROR", "DATABASE_ERROR", ...
    "AUTH_UNAVAILABLE"], ...
    ["authentication", "authentication", "permission", "permission", ...
    "not_found", "not_found", "invalid_request", "invalid_request", ...
    "invalid_request", "invalid_request", "outside_coverage", "rate_limited", ...
    "unavailable", "unavailable", "unavailable", "unavailable", "unavailable"]);
if ~isempty(code) && isKey(byCode, code)
    category = byCode(code);
    return
end
switch status
    case 400
        category = "invalid_request";
    case 401
        category = "authentication";
    case 403
        category = "permission";
    case {404, 410}
        category = "not_found";
    case 429
        category = "rate_limited";
    otherwise
        if status >= 500 && status <= 599
            category = "unavailable";
        else
            category = "api";
        end
end
end

function text = bodyText(body)
if isempty(body)
    text = "";
elseif ischar(body) || isstring(body)
    text = string(body);
else
    text = string(native2unicode(reshape(uint8(body), 1, []), "UTF-8"));
end
end

function seconds = maxAgeOf(headers)
% max-age in seconds, 0 for no-cache, NaN when absent.
seconds = NaN;
value = ensembleweather.internal.header(headers, "Cache-Control");
if isempty(value)
    return
end
if hasDirective(headers, "no-cache")
    seconds = 0;
    return
end
match = regexp(lower(value), "(?:^|,)\s*max-age\s*=\s*""?(\d+)", "tokens", "once");
if ~isempty(match)
    seconds = str2double(match{1});
end
end

function tf = hasDirective(headers, directive)
value = ensembleweather.internal.header(headers, "Cache-Control");
tf = false;
if isempty(value)
    return
end
names = strtrim(extractBefore(split(lower(value), ",") + "=", "="));
tf = any(names == directive);
end

function url = resolveUrl(base, location)
% Resolve a Location header against the URL that answered.
location = string(location);
if ~isempty(regexp(location, "^[A-Za-z][A-Za-z0-9+.-]*://", "once"))
    url = location;
    return
end
[scheme, authority, path] = splitUrl(base);
if startsWith(location, "//")
    url = scheme + ":" + location;
elseif startsWith(location, "/")
    url = scheme + "://" + authority + location;
else
    directory = regexprep(extractBefore(path + "?", "?"), "[^/]*$", "");
    url = scheme + "://" + authority + directory + location;
end
end

function tf = sameOrigin(a, b)
[schemeA, authorityA] = splitUrl(a);
[schemeB, authorityB] = splitUrl(b);
tf = lower(schemeA) == lower(schemeB) ...
    && withPort(lower(authorityA), schemeA) == withPort(lower(authorityB), schemeB);
end

function authority = withPort(authority, scheme)
if isempty(regexp(authority, ":\d+$", "once"))
    if lower(scheme) == "https"
        authority = authority + ":443";
    else
        authority = authority + ":80";
    end
end
end

function [scheme, authority, path] = splitUrl(url)
parts = regexp(url, "^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)(.*)$", "tokens", "once");
if isempty(parts)
    scheme = "";
    authority = "";
    path = string(url);
else
    scheme = string(parts{1});
    authority = string(parts{2});
    path = string(parts{3});
end
end

function tf = isTlsFailure(failure)
% A TLS verification failure is never retried.
text = lower(string(failure.identifier) + " " + failure.message);
tf = contains(text, ["certificate", "ssl", "tls"]);
end
