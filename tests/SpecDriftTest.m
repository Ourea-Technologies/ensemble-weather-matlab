classdef SpecDriftTest < matlab.unittest.TestCase
    %SPECDRIFTTEST The toolbox against the pinned spec in spec/ (SDK-STANDARD "Tests").
    %   * every operation in spec/openapi/v1/openapi.yaml has a Client method;
    %   * the decoding table was generated from this spec (scripts/gen_schema.py
    %     --check, run in CI, proves it is fresh);
    %   * the field renames are exactly BEHAVIOR.md 3.0's table, read from the
    %     pinned spec/BEHAVIOR.md, and no other field is renamed;
    %   * every response example in the spec decodes, under the SDK names.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Constant)
        % operationId -> Client method. getMapsToken is out of SDK scope for 0.x.
        Methods = dictionary( ...
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
            "alertOutlines", "avalancheZones"])
        OutOfScope = "getMapsToken"
    end

    properties (Access = private)
        Root
    end

    methods (TestClassSetup)
        function paths(testCase)
            here = fileparts(mfilename("fullpath"));
            testCase.Root = fileparts(here);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "toolbox")));
        end
    end

    methods (Test)
        function everyOperationHasAMethod(testCase)
            spec = fileread(fullfile(testCase.Root, "spec", "openapi", "v1", "openapi.yaml"));
            ids = regexprep(string(regexp(spec, "operationId:\s*\w+", "match")), ...
                "^operationId:\s*", "");
            ids = setdiff(ids, SpecDriftTest.OutOfScope);
            testCase.verifyNotEmpty(ids);
            exposed = string(methods("ensembleweather.Client"));
            for id = reshape(ids, 1, [])
                testCase.verifyTrue(isKey(SpecDriftTest.Methods, id), ...
                    "the spec has an operation this toolbox does not map: " + id);
                if isKey(SpecDriftTest.Methods, id)
                    testCase.verifyTrue(any(exposed == SpecDriftTest.Methods(id)), ...
                        id + ": no Client method " + SpecDriftTest.Methods(id));
                end
            end
            table = ensembleweather.internal.schemaTable();
            testCase.verifyEqual(sort(string(keys(table.Operations))), sort(ids), ...
                "schema.json's operations are the spec's");
        end

        function decodingTableIsForThePinnedSpec(testCase)
            version = strtrim(string(fileread(fullfile(testCase.Root, "spec", "VERSION"))));
            table = ensembleweather.internal.schemaTable();
            testCase.verifyEqual(table.Spec, version);
            examples = jsondecode(fileread(fullfile(testCase.Root, "tests", "fixtures", ...
                "spec-examples.json")));
            testCase.verifyEqual(string(examples.spec), version);
        end

        function renamesAreExactlyBehaviorTable(testCase)
            expected = SpecDriftTest.behaviorRenames(testCase.Root);
            testCase.verifyNotEmpty(expected);
            table = ensembleweather.internal.schemaTable();
            applied = strings(0, 1);
            names = keys(table.Objects);
            for i = 1:numel(names)
                entry = table.Objects(names{i});
                for k = 1:numel(entry.wire)
                    wire = string(entry.wire{k});
                    sdk = string(entry.sdk{k});
                    if wire == sdk || (iskeyword(wire) && sdk == wire + "_")
                        continue
                    end
                    applied(end + 1, 1) = string(names{i}) + "." + wire + "->" + sdk; %#ok<AGROW>
                end
            end
            missing = setdiff(expected, applied);
            extra = setdiff(applied, expected);
            testCase.verifyEmpty(missing, "BEHAVIOR.md 3.0 renames not applied: " ...
                + join(missing, ", "));
            testCase.verifyEmpty(extra, "renames not in BEHAVIOR.md 3.0: " + join(extra, ", "));
        end

        function keptNamesAreNotRenamed(testCase)
            % BEHAVIOR.md 3.0: these repeat no word of their holder, so they stay.
            table = ensembleweather.internal.schemaTable();
            kept = ["TimeSeriesPoint", "valid_time"; "TimeSeriesPoint", "lead_time_hours";
                "PrecipType", "type"; "FreezingLevel", "above_freezing_layer_aloft";
                "ModelRunInfo", "models"; "SnowpackAspect", "aspect";
                "ProbabilityResult", "window_start_hours"; "ForecastLocation", "elevation";
                "ExploreItem", "elevation"; "PassForecast", "elevation"];
            for i = 1:size(kept, 1)
                entry = table.Objects(char(kept(i, 1)));
                k = find(string(entry.wire) == kept(i, 2), 1);
                testCase.verifyNotEmpty(k, kept(i, 1) + "." + kept(i, 2) + " is in the spec");
                if ~isempty(k)
                    testCase.verifyEqual(string(entry.sdk{k}), kept(i, 2));
                end
            end
        end

        function everySpecExampleDecodes(testCase)
            file = jsondecode(fileread(fullfile(testCase.Root, "tests", "fixtures", ...
                "spec-examples.json")));
            examples = file.examples;
            testCase.verifyNotEmpty(examples);
            table = ensembleweather.internal.schemaTable();
            geo = ["getAlertOutlines", "getAvalancheZones"];
            for i = 1:numel(examples)
                ex = examples(i);
                name = string(ex.name);
                geojson = any(startsWith(name, geo + "#"));
                decoded = ensembleweather.internal.decode(jsondecode(ex.body), ex.type, geojson);
                testCase.verifyClass(decoded, "struct", name);
                object = extractAfter(string(ex.type), 2);
                entry = table.Objects(char(object));
                if geojson
                    want = entry.raw;
                else
                    want = entry.sdk;
                end
                testCase.verifyEqual(string(fieldnames(decoded))', string(want), name);
            end
        end

        function everyObjectDecodesFromEmpty(testCase)
            % An object with no fields sent decodes to the same shape (all []).
            table = ensembleweather.internal.schemaTable();
            names = keys(table.Objects);
            for i = 1:numel(names)
                decoded = ensembleweather.internal.decode(struct(), "o:" + names{i}, false);
                entry = table.Objects(names{i});
                if isempty(entry.sdk)
                    testCase.verifyEmpty(fieldnames(decoded), names{i});
                else
                    testCase.verifyEqual(fieldnames(decoded)', entry.sdk, names{i});
                end
            end
        end
    end

    methods (Static)
        function rows = behaviorRenames(root)
            % "Schema.wire->sdk" for every row of BEHAVIOR.md 3.0's table.
            text = string(fileread(fullfile(root, "spec", "BEHAVIOR.md"), "Encoding", "UTF-8"));
            section = extractBefore(extractAfter(text, "### 3.0"), "### 3.1");
            rows = strings(0, 1);
            for line = splitlines(section)'
                if ~startsWith(line, "| `")
                    continue
                end
                cells = strtrim(split(strip(strip(line), "|"), "|"));
                if numel(cells) ~= 3
                    continue
                end
                schemas = ticks(cells(1));
                wires = ticks(cells(2));
                sdks = ticks(cells(3));
                for s = schemas
                    if s == "ErrorResponse"
                        continue  % the error's Code, not a decoded field
                    end
                    for k = 1:numel(wires)
                        rows(end + 1, 1) = s + "." + wires(k) + "->" + sdks(k); %#ok<AGROW>
                    end
                end
            end
        end
    end
end

function names = ticks(text)
names = erase(string(regexp(text, "`[^`]+`", "match")), "`");
names = reshape(names, 1, []);
end
