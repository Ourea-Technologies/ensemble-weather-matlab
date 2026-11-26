classdef ClientTest < matlab.unittest.TestCase
    %CLIENTTEST Behaviour beyond the shared vectors: config, query form, cache,
    %   retries, errors, decoding, security properties and the helpers.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Access = private)
        Bodies
    end

    methods (TestClassSetup)
        function paths(testCase)
            here = fileparts(mfilename("fullpath"));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(here), "toolbox")));
            testCase.Bodies = fullfile(fileparts(here), "spec", "vectors", "bodies");
        end
    end

    methods (TestMethodSetup)
        function environment(testCase)
            import matlab.unittest.fixtures.EnvironmentVariableFixture
            testCase.applyFixture(EnvironmentVariableFixture("OUREA_API_KEY", ""));
            testCase.applyFixture(EnvironmentVariableFixture("OUREA_BASE_URL", ""));
            testCase.applyFixture(matlab.unittest.fixtures.SuppressedWarningsFixture( ...
                "ensembleweather:deprecated"));
            ensembleweather.internal.deprecation("reset");
        end
    end

    methods (Access = private)
        function text = readBody(testCase, name)
            text = string(fileread(fullfile(testCase.Bodies, name), "Encoding", "UTF-8"));
        end

        function [client, replay] = makeClient(testCase, varargin) %#ok<INUSL>
            replay = helpers.Replay();
            client = ensembleweather.Client("Transport", @(r) replay.send(r), ...
                "Sleep", @(s) replay.sleep(s), "Random", @() 1.0, varargin{:});
        end

        function verifyCategory(testCase, fn, category)
            try
                fn();
                testCase.verifyFail("expected an ensembleweather error: " + category);
            catch err
                testCase.verifyClass(err, "ensembleweather.OureaError");
                testCase.verifyEqual(err.Category, category, err.message);
            end
        end
    end

    methods (Test)
        % --- formatting ---------------------------------------------------------

        function numbersAreShortestWithoutExponent(testCase)
            f = @ensembleweather.internal.formatNumber;
            testCase.verifyEqual(f(1661), "1661");
            testCase.verifyEqual(f(45.3311), "45.3311");
            testCase.verifyEqual(f(-121.6649), "-121.6649");
            testCase.verifyEqual(f(2500.5), "2500.5");
            testCase.verifyEqual(f(0.1), "0.1");
            testCase.verifyEqual(f(1e-7), "0.0000001");
            testCase.verifyEqual(f(-0), "0");
            testCase.verifyEqual(f(1e20), "100000000000000000000");
            testCase.verifyEqual(f(123456.789), "123456.789");
            testCase.verifyCategory(@() f(Inf), "usage");
        end

        function valuesArePercentEncoded(testCase)
            e = @ensembleweather.internal.encode;
            testCase.verifyEqual(e("Mt. Hood & co/" + char(241)), "Mt.%20Hood%20%26%20co%2F%C3%B1");
            testCase.verifyEqual(e("a-b_c.d~e"), "a-b_c.d~e");
            testCase.verifyEqual(e("a,b:c+d"), "a%2Cb%3Ac%2Bd");
            testCase.verifyEqual(e(""), "");
        end

        function sha256MatchesTheStandard(testCase)
            h = @ensembleweather.internal.sha256;
            testCase.verifyEqual(h("abc"), ...
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
            testCase.verifyEqual(h(""), ...
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
            testCase.verifyEqual(strlength(h(repmat('k', 1, 200))), 64);
        end

        function queryIsCanonical(testCase)
            q = ensembleweather.internal.Query();
            q.add("units", "metric", "metric");
            q.add("max_hours", 72, 24);
            q.add("include_past", true, false);
            q.addList("sources", ["snotel", "asos", "snotel"]);
            q.add("q", "a b");
            testCase.verifyEqual(q.render(), "include_past=true&max_hours=72&q=a%20b&sources=asos,snotel");
        end

        function timestampsParseAsInstants(testCase)
            p = @ensembleweather.internal.parseTime;
            a = p("2026-11-25T04:00:00Z");
            testCase.verifyEqual(a, p("2026-11-24T20:00:00-08:00"));
            testCase.verifyEqual(a.TimeZone, 'UTC');
            testCase.verifyEqual(second(p("2026-11-25T04:00:00.250Z")), 0.25, "AbsTol", 1e-9);
            testCase.verifyError(@() p("yesterday"), "ensembleweather:internal:decode");
        end

        % --- probability terms ---------------------------------------------------

        function chanceValidatesBeforeSending(testCase)
            C = @ensembleweather.Chance;
            testCase.verifyCategory(@() C("hail", "ge", 1), "usage");
            testCase.verifyCategory(@() C("snowfall", "gt", 1), "usage");
            testCase.verifyCategory(@() C("snowfall", "ge", 1, Unit="degF"), "usage");
            testCase.verifyCategory(@() C("snowfall", "ge", 1, Aggregation="any"), "usage");
            testCase.verifyCategory(@() C("temperature", "ge", 1, Aggregation="total"), "usage");
            testCase.verifyCategory(@() C("snowfall", "ge", 1, Window=[24 12]), "usage");
            testCase.verifyCategory(@() C("snowfall", "ge", 1, Window=361), "usage");
            testCase.verifyCategory(@() C("snowfall", "ge", NaN), "usage");
        end

        function chanceWireForm(testCase)
            c = ensembleweather.Chance.atLeast("snowfall", 6, Unit="in");
            testCase.verifyEqual(c.wire("metric"), "snowfall:ge:152.40:24h");
            testCase.verifyEqual(c.wire("imperial"), "snowfall:ge:6.000:24h");
            k = ensembleweather.Chance.atMost("temperature", 273.15, Unit="K", Window=[6 18], ...
                Aggregation="all");
            testCase.verifyEqual(k.wire("metric"), "temperature:le:0.0:6-18h:all");
            testCase.verifyEqual(k.wire("kelvin"), "temperature:le:273.1:6-18h:all");
            m = ensembleweather.Chance.atLeast("wind_speed", 40, Unit="mph");
            testCase.verifyEqual(m.wire("metric"), "wind_speed:ge:17.9:24h");
            n = ensembleweather.Chance.atMost("temperature", -0.04);
            testCase.verifyEqual(n.wire("metric"), "temperature:le:0.0:24h");
        end

        function totalsValidate(testCase)
            testCase.verifyCategory(@() ensembleweather.Total("temperature", 24), "usage");
            testCase.verifyEqual(ensembleweather.Total("snowfall", [24 48]).wire(), "snowfall:24-48h");
        end

        % --- configuration and security -----------------------------------------

        function badConfigurationIsUsage(testCase)
            testCase.verifyCategory(@() ensembleweather.Client(Units="si"), "usage");
            testCase.verifyCategory(@() ensembleweather.Client(Timeout=0), "usage");
            testCase.verifyCategory(@() ensembleweather.Client(MaxRetries=-1), "usage");
            testCase.verifyCategory(@() ensembleweather.Client(Cache="yes"), "usage");
            testCase.verifyCategory(@() ensembleweather.Client(BaseUrl="ftp://x"), "usage");
        end

        function keyIsNeverDisplayed(testCase)
            client = ensembleweather.Client(ApiKey="ow_secret_value_123");
            testCase.verifyTrue(client.HasApiKey);
            testCase.verifyFalse(contains(formattedDisplayText(client), "ow_secret_value_123"));
            testCase.verifyFalse(contains(formattedDisplayText(client, "SuppressMarkup", true), ...
                "ow_secret_value_123"));
            names = string(properties(client));
            testCase.verifyFalse(any(contains(lower(names), "key") & names ~= "HasApiKey"));
        end

        function keyIsScrubbedFromErrors(testCase)
            [client, replay] = testCase.makeClient(ApiKey="ow_leaky");
            replay.add(400, ["Content-Type", "application/json"], ...
                "{""error"":""BAD_REQUEST"",""message"":""bad key ow_leaky here""}");
            try
                client.attribution();
                testCase.verifyFail("expected an error");
            catch err
                testCase.verifyFalse(contains(err.message, "ow_leaky"));
                testCase.verifyFalse(contains(getReport(err), "ow_leaky"));
            end
        end

        function userAgentNamesTheToolbox(testCase)
            client = ensembleweather.Client(AppUserAgent="my-app/1.2");
            testCase.verifyTrue(startsWith(client.UserAgent, ...
                "ensemble-weather-matlab/" + ensembleweather.Client.Version + " (MATLAB/R"));
            testCase.verifyTrue(endsWith(client.UserAgent, ") my-app/1.2"));
        end

        function baseUrlFromEnvironment(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "OUREA_BASE_URL", "http://127.0.0.1:9/"));
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/json"], testCase.readBody("attribution.json"));
            client.attribution();
            testCase.verifyEqual(replay.Requests{1}.url, "http://127.0.0.1:9/api/v1/attribution");
        end

        function oversizedBodyIsAnError(testCase)
            replay = helpers.Replay();
            big = struct("status", 200, "headers", strings(0, 2), ...
                "body", zeros(1, 64 * 1024 * 1024 + 1, "uint8"));
            client = ensembleweather.Client(Transport=@(r) big);
            testCase.verifyCategory(@() client.attribution(), "unexpected_response");
            testCase.verifyEmpty(replay.Requests);
        end

        % --- cache -------------------------------------------------------------

        function memoryCacheIsBounded(testCase)
            cache = ensembleweather.MemoryCache(MaxEntries=2, MaxBytes=10);
            entry = @(n) struct("body", repmat('x', 1, n), "etag", """e""", ...
                "headers", strings(0, 2), "storedAt", 0, "maxAge", NaN);
            cache.set("a", entry(2));
            cache.set("b", entry(2));
            cache.set("c", entry(2));
            testCase.verifyEqual(cache.Count, 2);
            testCase.verifyEmpty(cache.get("a"));
            cache.set("big", entry(11));
            testCase.verifyEmpty(cache.get("big"));
            cache.set("d", entry(6));
            testCase.verifyLessThanOrEqual(cache.SizeBytes, 10);
        end

        function positiveMaxAgeServesWithoutARequest(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/json"; "Cache-Control", "max-age=300"], ...
                testCase.readBody("attribution.json"));
            client.attribution();
            [~, meta] = client.attribution();
            testCase.verifyNumElements(replay.Requests, 1);
            testCase.verifyTrue(meta.from_cache);
            testCase.verifyFalse(meta.revalidated);
        end

        function retryKeepsIfNoneMatch(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["ETag", """a"""], testCase.readBody("attribution.json"));
            replay.add(503, ["Content-Type", "application/json"], testCase.readBody("error-unavailable.json"));
            replay.add(304, ["ETag", """a"""], "");
            client.attribution();
            [~, meta] = client.attribution();
            sent = cellfun(@(r) string(ensembleweather.internal.header(r.headers, "If-None-Match")), ...
                replay.Requests(2:3));
            testCase.verifyEqual(sent, ["""a""", """a"""]);
            testCase.verifyTrue(meta.revalidated);
        end

        function customCacheIsUsed(testCase)
            store = ensembleweather.MemoryCache();
            [client, replay] = testCase.makeClient(Cache=store);
            replay.add(200, ["ETag", """z"""], testCase.readBody("attribution.json"));
            client.attribution();
            testCase.verifyEqual(store.Count, 1);
            testCase.verifySameHandle(client.Cache, store);
        end

        % --- retries and errors --------------------------------------------------

        function backoffIsCappedFullJitter(testCase)
            [client, replay] = testCase.makeClient(MaxRetries=6);
            for k = 1:6
                replay.add(502, strings(0, 2), "bad gateway");
            end
            replay.add(200, strings(0, 2), testCase.readBody("attribution.json"));
            client.attribution();
            testCase.verifyEqual(replay.Delays, [0.5 1 2 4 8 8]);
        end

        function retryAfterOn504(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(504, ["Retry-After", "5"], testCase.readBody("error-unavailable.json"));
            replay.add(200, strings(0, 2), testCase.readBody("attribution.json"));
            client.attribution();
            testCase.verifyEqual(replay.Delays, 5);
        end

        function retryAfterHttpDate(testCase)
            now = 1.8e9;
            date = string(datetime(now + 7, "ConvertFrom", "posixtime", "TimeZone", "UTC"), ...
                "eee, dd MMM yyyy HH:mm:ss 'GMT'", "en_US");
            testCase.verifyEqual(ensembleweather.internal.retryAfter(date, now), 7, "AbsTol", 1e-6);
            testCase.verifyEqual(ensembleweather.internal.retryAfter("5", now), 5);
            testCase.verifyEmpty(ensembleweather.internal.retryAfter("soon", now));
        end

        function connectionErrorsAreRetried(testCase)
            attempts = helpers.Replay();
            ok = struct("status", 200, "headers", strings(0, 2), ...
                "body", unicode2native('{"providers": []}', "UTF-8"));
            client = ensembleweather.Client(Sleep=@(s) attempts.sleep(s), Random=@() 1.0, ...
                Transport=@(r) flaky(attempts, ok));
            result = client.attribution();
            testCase.verifyEmpty(result.providers);
            testCase.verifyNumElements(attempts.Delays, 2);

            down = ensembleweather.Client(MaxRetries=1, Sleep=@(s) attempts.sleep(s), ...
                Transport=@(r) failWith("MATLAB:webservices:Timeout", "timed out"));
            testCase.verifyCategory(@() down.attribution(), "connection");
        end

        function tlsFailuresAreNotRetried(testCase)
            log = helpers.Replay();
            client = ensembleweather.Client(Sleep=@(s) log.sleep(s), ...
                Transport=@(r) failWith("MATLAB:webservices:SSLConnectionFailure", ...
                "SSL certificate problem: unable to get local issuer certificate"));
            testCase.verifyCategory(@() client.attribution(), "connection");
            testCase.verifyEmpty(log.Delays);
        end

        function rateLimitErrorCarriesState(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(429, ["Content-Type", "application/json"; "Retry-After", "120"; ...
                "RateLimit-Remaining", "0"; "X-Request-Id", "req-1"], ...
                testCase.readBody("error-rate-limited.json"));
            try
                client.attribution();
                testCase.verifyFail("expected an error");
            catch err
                testCase.verifyEqual(err.identifier, 'ensembleweather:rateLimited');
                testCase.verifyEqual(err.RetryAfter, 120);
                testCase.verifyEqual(err.RequestId, "01JBQ6ZK3V8M4T2N7XQH5R9W0C");
                testCase.verifyEqual(err.DocUrl, ...
                    "https://docs.oureawx.com/features/errors/#too_many_requests");
                testCase.verifyEqual(err.RateLimit.remaining, 0);
            end
            testCase.verifyNotEmpty(client.RateLimit);
        end

        function plusRequiredIsPermission(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(403, ["Content-Type", "application/json"], ...
                "{""error"":""PLUS_REQUIRED"",""message"":""Plus or Pro.""}");
            testCase.verifyCategory(@() client.snowTrend("or/mt-hood-meadows"), "permission");
        end

        function proRequiredNamesTheNearestLocation(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(403, ["Content-Type", "application/json"], ...
                "{""error"":""PRO_REQUIRED"",""message"":""Pro."",""nearest_location"":" ...
                + "{""slug"":""mt-hood-meadows"",""url"":""/api/v1/locations/or/mt-hood-meadows""," ...
                + """distance_km"":4.25}}");
            try
                client.getPointForecast(45.33, -121.67);
                testCase.verifyFail("expected an error");
            catch err
                testCase.verifyEqual(err.Category, "permission");
                testCase.verifyEqual(string(err.NearestLocation.url), ...
                    "/api/v1/locations/or/mt-hood-meadows");
            end
        end

        function badRequestNamesItsParam(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(400, ["Content-Type", "application/json"], ...
                "{""error"":""BAD_REQUEST"",""message"":""Unknown include."",""param"":""include""}");
            try
                client.forecast("or/mt-hood-meadows", Include="nope");
                testCase.verifyFail("expected an error");
            catch err
                testCase.verifyEqual(err.Param, "include");
            end
        end

        function missingAnswerIsUnexpected(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/json"], ...
                testCase.readBody("forecast-prob-snow.json"));
            testCase.verifyCategory(@() client.forecast("or/mt-hood-meadows", Units="imperial", ...
                Prob=ensembleweather.Chance.atLeast("snowfall", 7, Unit="in")), ...
                "unexpected_response");
        end

        function malformedBodyIsUnexpected(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, strings(0, 2), "{""providers"": ""nope""}");
            testCase.verifyCategory(@() client.attribution(), "unexpected_response");
            replay.add(200, strings(0, 2), "not json");
            testCase.verifyCategory(@() client.attribution(), "unexpected_response");
        end

        function argumentsAreCheckedBeforeSending(testCase)
            [client, replay] = testCase.makeClient();
            testCase.verifyCategory(@() client.forecast("or/x", Members="all"), "usage");
            testCase.verifyCategory(@() client.forecast("mt-hood-meadows"), "usage");
            testCase.verifyCategory(@() client.search("hood", Near="45,-121"), "usage");
            testCase.verifyCategory(@() client.search("hood", Near=[95 0]), "usage");
            testCase.verifyCategory(@() client.alertOutlines(Bbox=[-116 41 -125 49]), "usage");
            testCase.verifyCategory(@() client.search("h"), "usage");
            testCase.verifyCategory(@() client.explore("snow_5d", Points="some"), "usage");
            testCase.verifyCategory(@() client.getPointForecast(91, 0), "usage");
            testCase.verifyCategory(@() client.forecast("or/x", Daily="yes"), "usage");
            testCase.verifyEmpty(replay.Requests);
        end

        function deprecationWarnsOncePerOperation(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.SuppressedWarningsFixture( ...
                "ensembleweather:deprecated"));
            [client, replay] = testCase.makeClient(Cache=false);
            for k = 1:3
                replay.add(200, ["Sunset", "Wed, 01 Dec 2027 00:00:00 GMT"], ...
                    testCase.readBody("attribution.json"));
            end
            client.attribution();
            client.attribution();
            client.attribution();
            emitted = ensembleweather.internal.deprecation("emitted");
            testCase.verifyNumElements(emitted, 1);
            testCase.verifySubstring(emitted(1), "getAttribution");
        end

        function deprecationIsAMatlabWarning(testCase)
            ensembleweather.internal.deprecation("reset");
            warning("on", "ensembleweather:deprecated");
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Deprecation", "@1798761600"], testCase.readBody("attribution.json"));
            testCase.verifyWarning(@() client.attribution(), "ensembleweather:deprecated");
        end

        % --- decoding -------------------------------------------------------------

        function forecastDecodesToStructsAndDatetimes(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/json"], ...
                testCase.readBody("forecast-metric.json"));
            [forecast, meta] = client.forecast("or/mt-hood-meadows");
            hours = forecast.series.timeseries;
            testCase.verifyClass(hours, "struct");
            testCase.verifySize(hours, [3 1]);
            testCase.verifyClass(hours(1).valid_time, "datetime");
            testCase.verifyEqual(hours(1).valid_time.TimeZone, 'UTC');
            testCase.verifyEqual(forecast.units, "metric");
            testCase.verifyEqual(meta.status, 200);
            testCase.verifyFalse(isfield(forecast, "forecast"));
        end

        function geojsonKeepsWireKeys(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/geo+json"], ...
                testCase.readBody("avalanche-zones.json"));
            zones = client.avalancheZones();
            testCase.verifyTrue(isfield(zones.features(1).properties, "forecast_url"));
            testCase.verifyFalse(isfield(zones.features(1).properties, "url"));
            testCase.verifyNotEmpty(zones.features(1).geometry.coordinates);
        end

        function snowpackDefinitionsAreDictionaries(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/json"], testCase.readBody("snowpack.json"));
            pack = client.snowpack("or/mt-hood-meadows");
            testCase.verifyClass(pack.definitions.layer_form, "dictionary");
            testCase.verifyTrue(isKey(pack.definitions.layer_form, "buried_surface_hoar"));
        end

        function iteratorFollowsCursorLazily(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, strings(0, 2), testCase.readBody("catalog-page-1.json"));
            replay.add(200, strings(0, 2), testCase.readBody("catalog-page-2.json"));
            pages = client.iterCatalogLocations();
            testCase.verifyEmpty(replay.Requests);
            first = pages.next();
            testCase.verifyEqual(first.slug, "mt-hood-meadows");
            testCase.verifyNumElements(replay.Requests, 1);
            rest = pages.collect();
            testCase.verifyEqual([rest.slug], "timberline-lodge");
            testCase.verifyFalse(pages.hasNext());
            testCase.verifyCategory(@() pages.next(), "usage");
            testCase.verifySubstring(replay.Requests{2}.url, "cursor=c2");
        end

        % --- helpers ----------------------------------------------------------------

        function timetableOfQuantiles(testCase)
            [client, replay] = testCase.makeClient();
            replay.add(200, ["Content-Type", "application/json"], ...
                testCase.readBody("forecast-metric.json"));
            forecast = client.forecast("or/mt-hood-meadows");
            tt = ensembleweather.toTimetable(forecast);
            testCase.verifyClass(tt, "timetable");
            testCase.verifyEqual(height(tt), 3);
            testCase.verifyEqual(tt.temperature_p50(1), ...
                forecast.series.timeseries(1).ensemble.temperature.p50);
            testCase.verifyEqual(tt.Time(1), forecast.series.timeseries(1).valid_time);
            testCase.verifyCategory(@() ensembleweather.toTimetable(42), "usage");
        end

        function intervalOnlyServedPairs(testCase)
            q = struct("p10", 1, "p25", 2, "p50", 3, "p75", 4, "p90", 5);
            testCase.verifyEqual(ensembleweather.interval(q), [1 5]);
            testCase.verifyEqual(ensembleweather.interval(q, 25, 75), [2 4]);
            testCase.verifyCategory(@() ensembleweather.interval(q, 5, 95), "usage");
        end

        function errorIdentifiers(testCase)
            e = ensembleweather.OureaError("outside_coverage", "x");
            testCase.verifyEqual(e.identifier, 'ensembleweather:outsideCoverage');
            e = ensembleweather.OureaError("unexpected_response", "x");
            testCase.verifyEqual(e.identifier, 'ensembleweather:unexpectedResponse');
        end
    end
end

function response = flaky(log, ok)
% Fails twice with a connection error, then answers OK.
log.Requests{end + 1} = 1;
if numel(log.Requests) < 3
    error("MATLAB:webservices:ConnectionRefused", "connection reset");
end
response = ok;
end

function response = failWith(id, message)
% A transport that fails with no response.
response = [];
error(id, "%s", message);
end
