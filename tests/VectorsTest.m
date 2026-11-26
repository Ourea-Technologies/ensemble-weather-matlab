classdef VectorsTest < matlab.unittest.TestCase
    %VECTORSTEST Runs every shared vector in spec/vectors (BEHAVIOR.md 13).
    %   Each vector runs against a mock transport (helpers.Replay) that
    %   answers with the vector's responses and records the requests. A
    %   vector this runner cannot execute fails; nothing is skipped. The
    %   only per-language code is plan(), which maps a vector's semantic
    %   operation and arguments onto this toolbox's methods.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Constant)
        ExpectedVectorCount = 58
    end

    properties (TestParameter)
        vector = VectorsTest.cases()
    end

    methods (Static)
        function cases = cases()
            root = VectorsTest.vectorsFolder();
            files = dir(fullfile(root, "**", "*.json"));
            cases = struct();
            for i = 1:numel(files)
                folder = string(files(i).folder);
                relative = extractAfter(folder, strlength(root) + 1);
                if startsWith(relative, "bodies")
                    continue
                end
                name = relative + "/" + extractBefore(string(files(i).name), ".json");
                cases.(matlab.lang.makeValidName(replace(name, ["/", "-"], "_"))) = ...
                    fullfile(folder, files(i).name);
            end
        end

        function root = vectorsFolder()
            root = string(fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
                "spec", "vectors"));
        end
    end

    methods (TestClassSetup)
        function paths(testCase)
            here = fileparts(mfilename("fullpath"));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(here), "toolbox")));
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

    methods (Test)
        function everyVectorIsCollected(testCase)
            testCase.verifyEqual(numel(fieldnames(VectorsTest.cases())), ...
                VectorsTest.ExpectedVectorCount);
        end

        function runVector(testCase, vector)
            import matlab.unittest.fixtures.EnvironmentVariableFixture
            spec = helpers.parseJson(fileread(vector, "Encoding", "UTF-8"));
            config = field(spec, "client", containers.Map());
            env = field(config, "env", containers.Map());
            names = keys(env);
            for k = 1:numel(names)
                testCase.applyFixture(EnvironmentVariableFixture(names{k}, env(names{k})));
            end
            replay = helpers.Replay(field(spec, "responses", {}), VectorsTest.vectorsFolder());
            main = VectorsTest.makeClient(config, replay, struct());
            if isKey(spec, "calls")
                calls = spec("calls");
            else
                calls = {spec("call")};
            end
            results = {};
            metas = {};
            failure = [];
            try
                for k = 1:numel(calls)
                    c = calls{k};
                    client = main;
                    if isKey(c, "with_api_key")
                        shared = main.Cache;
                        if isempty(shared)
                            shared = false;
                        end
                        client = VectorsTest.makeClient(config, replay, ...
                            struct("ApiKey", c("with_api_key"), "Cache", shared));
                    end
                    [result, meta] = VectorsTest.invoke(client, c);
                    results{end + 1} = result; %#ok<AGROW>
                    metas{end + 1} = meta; %#ok<AGROW>
                end
            catch caught
                if ~isa(caught, "ensembleweather.OureaError")
                    rethrow(caught);
                end
                failure = caught;
            end

            expect = field(spec, "expect", containers.Map());
            if isKey(expect, "error")
                testCase.assertNotEmpty(failure, "expected an error");
                VectorsTest.checkError(testCase, failure, expect("error"));
            elseif ~isempty(failure)
                testCase.verifyFail("unexpected error: " + failure.message);
                return
            end

            requests = replay.Requests;
            if isKey(spec, "expect_request")
                wanted = spec("expect_request");
                if isempty(wanted)
                    testCase.verifyEmpty(requests, "no request may be sent");
                else
                    testCase.verifyNotEmpty(requests, "no request was sent");
                    for k = 1:numel(requests)
                        VectorsTest.checkRequest(testCase, requests{k}, wanted);
                    end
                end
            end
            if isKey(spec, "expect_requests")
                wanted = spec("expect_requests");
                testCase.verifyNumElements(requests, numel(wanted));
                for k = 1:min(numel(wanted), numel(requests))
                    VectorsTest.checkRequest(testCase, requests{k}, wanted{k});
                end
            end
            if isKey(expect, "requests")
                testCase.verifyNumElements(requests, expect("requests"));
            end
            if isKey(expect, "delays_s")
                delays = cell2mat(expect("delays_s"));
                if isempty(delays)
                    testCase.verifyEmpty(replay.Delays);
                else
                    testCase.verifyEqual(replay.Delays, delays, "AbsTol", 1e-9);
                end
            end
            if isKey(expect, "result")
                VectorsTest.checkResult(testCase, results{1}, metas{1}, expect("result"));
            end
            if isKey(expect, "results")
                wanted = expect("results");
                testCase.verifyNumElements(results, numel(wanted));
                for k = 1:min(numel(wanted), numel(results))
                    VectorsTest.checkResult(testCase, results{k}, metas{k}, wanted{k});
                end
            end
            if isKey(expect, "items")
                slugs = [results{end}.slug];
                testCase.verifyEqual(slugs, string(expect("items")));
            end
            emitted = ensembleweather.internal.deprecation("emitted");
            warnings = field(expect, "warnings", {});
            testCase.verifyNumElements(emitted, numel(warnings));
            for k = 1:min(numel(warnings), numel(emitted))
                testCase.verifySubstring(emitted(k), warnings{k}("contains"));
            end
        end
    end

    methods (Static)
        function client = makeClient(config, replay, overrides)
            args = {"Transport", @(request) replay.send(request), ...
                "Sleep", @(seconds) replay.sleep(seconds), "Random", @() 1.0};
            map = ["api_key", "ApiKey"; "base_url", "BaseUrl"; "max_retries", "MaxRetries";
                "cache", "Cache"; "send_key_on_open_routes", "SendKeyOnOpenRoutes"];
            for k = 1:size(map, 1)
                if isfield(overrides, map(k, 2))
                    args = [args, {map(k, 2), overrides.(map(k, 2))}]; %#ok<AGROW>
                elseif isKey(config, map(k, 1))
                    args = [args, {map(k, 2), config(map(k, 1))}]; %#ok<AGROW>
                end
            end
            client = ensembleweather.Client(args{:});
        end

        function [result, meta] = invoke(client, call)
            % plan(): the vector's operation and semantic args -> this toolbox's API.
            operation = call("operation");
            args = field(call, "args", containers.Map());
            names = keys(args);
            iterate = isKey(args, "iterate") && args("iterate");
            routes = dictionary( ...
                ["getLocationForecast", "getPointForecast", "getCurrentConditions", ...
                "getCurrentByCoordinates", "getLocationAlerts", "getAlertsByCoordinates", ...
                "getNearbyLocations", "getNearbyByCoordinates", "searchLocations", ...
                "getAllLocations", "getLocations", "listCatalogLocations", ...
                "getCatalogLocation", "listCatalogStations", "getCatalogStation", ...
                "getAvailableRuns", "getAttribution", "explore", "getComposition", ...
                "getLocationSeason", "getLocationSnowTrend", "getLocationSnowpack", ...
                "getLocationSnowpackPlume", "getAlertOutlines", "getAvalancheZones"], ...
                ["forecast", "getPointForecast", "current", "getPointCurrent", "alerts", ...
                "getPointAlerts", "nearby", "getPointNearby", "search", "listLocations", ...
                "listLocations", "listCatalogLocations", "catalogLocation", ...
                "listCatalogStations", "catalogStation", "runs", "attribution", "explore", ...
                "composition", "season", "snowTrend", "snowpack", "snowpackPlume", ...
                "alertOutlines", "avalancheZones"]);
            method = routes(operation);
            if iterate
                iterators = dictionary(["listLocations", "listCatalogLocations", ...
                    "listCatalogStations", "runs", "explore"], ["iterLocations", ...
                    "iterCatalogLocations", "iterCatalogStations", "iterRuns", "iterExplore"]);
                method = iterators(method);
            end
            positional = {};
            locationOps = ["forecast", "current", "alerts", "nearby", "season", ...
                "snowTrend", "snowpack", "snowpackPlume"];
            if any(method == locationOps)
                if isKey(args, "location")
                    positional = {args("location")};
                else
                    positional = {args("state") + "/" + args("slug")};
                end
            elseif any(method == ["getPointForecast", "getPointCurrent", ...
                    "getPointAlerts", "getPointNearby"])
                positional = {args("lat"), args("lon")};
            elseif method == "search"
                positional = {args("q")};
            elseif any(method == ["catalogLocation", "catalogStation"])
                positional = {args("slug")};
            elseif any(method == ["explore", "iterExplore"])
                positional = {args("metric")};
            end
            used = ["location", "lat", "lon", "q", "metric", "iterate"];
            if any(method == [locationOps, "catalogLocation", "catalogStation"])
                used = [used, "state", "slug"];
            end
            options = {};
            for k = 1:numel(names)
                name = string(names{k});
                if any(name == used)
                    continue
                end
                value = args(char(name));
                switch name
                    case "prob"
                        value = cellfun(@VectorsTest.chance, value, "UniformOutput", false);
                        value = [value{:}];
                        option = "Prob";
                    case "totals"
                        value = cellfun(@VectorsTest.total, value, "UniformOutput", false);
                        value = [value{:}];
                        option = "Totals";
                    case "near"
                        value = [value("lat"), value("lon")];
                        option = "Near";
                    case "bbox"
                        value = [value("west"), value("south"), value("east"), value("north")];
                        option = "Bbox";
                    case "elevation_m"
                        option = "Elevation";
                    case "capability"
                        option = "Capabilities";
                    case "include"
                        if method == "season"
                            option = "IncludeDaily";
                            value = any(string(value) == "daily");
                        else
                            option = "Include";
                        end
                    otherwise
                        option = join(upper(extractBefore(split(name, "_"), 2)) ...
                            + extractAfter(split(name, "_"), 1), "");
                end
                if iscell(value)
                    value = string(value);
                end
                options = [options, {option, value}]; %#ok<AGROW>
            end
            if iterate
                result = client.(method)(positional{:}, options{:}).collect();
                meta = struct();
            else
                [result, meta] = client.(method)(positional{:}, options{:});
            end
        end

        function c = chance(term)
            threshold = term("threshold");
            c = ensembleweather.Chance(term("variable"), term("op"), threshold("value"), ...
                Unit=field(threshold, "unit", ""), Window=VectorsTest.window(term), ...
                Aggregation=field(term, "aggregation", ""));
        end

        function t = total(spec)
            t = ensembleweather.Total(spec("variable"), VectorsTest.window(spec));
        end

        function w = window(term)
            w = 24;
            if isKey(term, "window")
                spec = term("window");
                if isKey(spec, "hours")
                    w = spec("hours");
                else
                    w = [spec("start_hours"), spec("end_hours")];
                end
            end
        end

        % --- checking -----------------------------------------------------------

        function checkRequest(testCase, request, wanted)
            url = string(request.url);
            label = "GET " + url;
            target = extractAfter(url, "://");
            path = "/" + extractAfter(extractBefore(target + "?", "?"), "/");
            query = "";
            if contains(url, "?")
                query = extractAfter(url, "?");
            end
            if isKey(wanted, "method")
                testCase.verifyEqual(string(request.method), wanted("method"), label);
            end
            if isKey(wanted, "path")
                testCase.verifyEqual(path, wanted("path"), label);
            end
            if isKey(wanted, "url_prefix")
                testCase.verifyTrue(startsWith(url, wanted("url_prefix")), label);
            end
            if isKey(wanted, "query_string")
                testCase.verifyEqual(query, wanted("query_string"), label);
            end
            pairs = strings(0, 2);
            if strlength(query) > 0
                for item = split(query, "&")'
                    nv = split(item + "=", "=");
                    pairs(end + 1, :) = [percentDecode(nv(1)), percentDecode(nv(2))]; %#ok<AGROW>
                end
            end
            testCase.verifyEqual(numel(unique(pairs(:, 1))), size(pairs, 1), ...
                label + ": a parameter is repeated");
            if isKey(wanted, "query")
                q = wanted("query");
                qnames = keys(q);
                for k = 1:numel(qnames)
                    found = pairs(:, 1) == qnames{k} & pairs(:, 2) == q(qnames{k});
                    testCase.verifyTrue(any(found), label + ": expected " + qnames{k} ...
                        + "=" + q(qnames{k}));
                end
            end
            for name = string(field(wanted, "query_absent", {}))
                testCase.verifyFalse(any(pairs(:, 1) == name), label + ": " + name ...
                    + " must be absent");
            end
            headers = request.headers;
            h = field(wanted, "headers", containers.Map());
            hnames = keys(h);
            for k = 1:numel(hnames)
                testCase.verifyEqual(ensembleweather.internal.header(headers, hnames{k}), ...
                    h(hnames{k}), label + ": header " + hnames{k});
            end
            for name = string(field(wanted, "headers_absent", {}))
                testCase.verifyEmpty(ensembleweather.internal.header(headers, name), ...
                    label + ": header " + name + " must be absent");
            end
            m = field(wanted, "headers_match", containers.Map());
            mnames = keys(m);
            for k = 1:numel(mnames)
                value = ensembleweather.internal.header(headers, mnames{k});
                testCase.verifyNotEmpty(value, label + ": header " + mnames{k});
                testCase.verifyNotEmpty(regexp(value, m(mnames{k}), "once"), ...
                    label + ": header " + mnames{k} + " = " + value);
            end
        end

        function checkResult(testCase, result, meta, wanted)
            paths = keys(wanted);
            for k = 1:numel(paths)
                path = string(paths{k});
                actual = VectorsTest.resolve(result, meta, path);
                VectorsTest.checkValue(testCase, path, actual, wanted(paths{k}));
            end
        end

        function value = resolve(result, meta, path)
            % Follow a dot-and-[i] path (BEHAVIOR.md 13) through the result.
            tokens = regexp(path, "[^.\[\]]+|\[\d+\]", "match");
            value = result;
            for k = 1:numel(tokens)
                token = tokens(k);
                if isempty(value)
                    value = [];
                    return
                end
                if startsWith(token, "[")
                    index = str2double(extractBetween(token, 2, strlength(token) - 1)) + 1;
                    if iscell(value)
                        value = value{index};
                    elseif ismatrix(value) && size(value, 1) > 1 && size(value, 2) > 1
                        value = value(index, :);
                    else
                        value = value(index);
                    end
                    continue
                end
                name = token;
                if k == 1 && any(name == ["revalidated", "rate_limit"])
                    value = meta.(name);
                    continue
                end
                if iskeyword(name)
                    name = name + "_";
                end
                if ~isstruct(value) || ~isfield(value, name)
                    error("helpers:path", "%s: no field %s", path, name);
                end
                value = value.(name);
            end
        end

        function checkValue(testCase, path, actual, expected)
            label = path;
            if isa(expected, "containers.Map") && isKey(expected, "unknown")
                raw = expected("unknown");
                testCase.verifyEqual(actual, raw, label);
                table = ensembleweather.internal.schemaTable();
                known = values(table.Enums);
                testCase.verifyFalse(any(cellfun(@(v) any(v == raw), known)), ...
                    label + ": " + raw + " is a known enum value");
            elseif isempty(expected) && isnumeric(expected)
                testCase.verifyTrue(isempty(actual) || all(ismissing(actual)), ...
                    label + ": expected absent");
            elseif islogical(expected)
                testCase.verifyClass(actual, "logical", label);
                testCase.verifyEqual(actual, expected, label);
            elseif isnumeric(expected)
                testCase.verifyTrue(isnumeric(actual) && isscalar(actual), ...
                    label + ": not a number");
                testCase.verifyEqual(double(actual), expected, "RelTol", 1e-12, label);
            elseif isdatetime(actual)
                testCase.verifyEqual(actual, ensembleweather.internal.parseTime(expected), ...
                    label);
            else
                testCase.verifyClass(actual, "string", label);
                testCase.verifyEqual(actual, expected, label);
            end
        end

        function checkError(testCase, failure, wanted)
            testCase.verifyEqual(failure.Category, wanted("category"), failure.message);
            words = split(wanted("category"), "_");
            words(2:end) = upper(extractBefore(words(2:end), 2)) + extractAfter(words(2:end), 1);
            testCase.verifyEqual(string(failure.identifier), "ensembleweather:" + join(words, ""));
            pairs = ["code", "Code"; "status", "Status"; "retry_after", "RetryAfter"];
            for k = 1:size(pairs, 1)
                if isKey(wanted, pairs(k, 1))
                    VectorsTest.checkValue(testCase, pairs(k, 1), failure.(pairs(k, 2)), ...
                        wanted(pairs(k, 1)));
                end
            end
            if isKey(wanted, "string_excludes")
                secret = wanted("string_excludes");
                testCase.verifyFalse(contains(failure.message, secret));
                testCase.verifyFalse(contains(string(getReport(failure)), secret));
                testCase.verifyFalse(contains(string(formattedDisplayText(failure)), secret));
            end
        end
    end
end

function value = field(map, key, default)
if isKey(map, key)
    value = map(key);
else
    value = default;
end
end

function text = percentDecode(text)
bytes = uint8([]);
raw = char(text);
i = 1;
while i <= numel(raw)
    if raw(i) == '%' && i + 2 <= numel(raw)
        bytes(end + 1) = uint8(hex2dec(raw(i + 1:i + 2))); %#ok<AGROW>
        i = i + 3;
    else
        bytes(end + 1) = uint8(raw(i)); %#ok<AGROW>
        i = i + 1;
    end
end
text = string(native2unicode(bytes, "UTF-8"));
end
