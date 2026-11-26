classdef LiveBodiesTest < matlab.unittest.TestCase
    %LIVEBODIESTEST The decoder on real keyed responses (tests/fixtures/live).
    %   Bodies captured from api.oureawx.com with a Pro key: members and
    %   per-model means at every elevation, a point forecast, current
    %   conditions at a point and the snow trend. Each goes through the
    %   client (a replaying transport), so the full decode path runs.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Access = private)
        Folder
    end

    methods (TestClassSetup)
        function paths(testCase)
            here = fileparts(mfilename("fullpath"));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(here));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(fileparts(here), "toolbox")));
            testCase.Folder = fullfile(here, "fixtures", "live");
        end
    end

    methods (Access = private)
        function client = replaying(testCase, name)
            folder = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            file = gunzip(fullfile(testCase.Folder, name + ".json.gz"), folder);
            replay = helpers.Replay();
            replay.add(200, ["Content-Type", "application/json"], ...
                string(fileread(file{1}, "Encoding", "UTF-8")));
            client = ensembleweather.Client(ApiKey="ow_fixture", Transport=@(r) replay.send(r));
        end
    end

    methods (Test)
        function membersAndModelsAtEveryElevation(testCase)
            client = testCase.replaying("members");
            started = tic;
            f = client.forecast("or/mt-hood-meadows", Elevations="all", MaxHours=12, ...
                Members=true, Models=true);
            fprintf("decoded the members body in %.2f s\n", toc(started));
            hour = f.series.timeseries(1);
            testCase.verifyClass(hour.members, "struct");
            testCase.verifyClass(hour.members(1).items, "struct");
            testCase.verifyTrue(isfield(hour.members(1).items, "id"));
            testCase.verifyFalse(isfield(hour.members(1).items, "member_id"));
            testCase.verifyClass(hour.model_means, "struct");
            testCase.verifyGreaterThanOrEqual(numel(f.elevations), 1);
            testCase.verifyTrue(isnumeric(f.elevations(1).height));
            testCase.verifyClass(f.elevations(1).hourly, "struct");
            testCase.verifyClass(f.current.code, "string");
            tt = ensembleweather.toTimetable(f.elevations(1).hourly);
            testCase.verifyEqual(height(tt), numel(f.elevations(1).hourly));
        end

        function pointForecast(testCase)
            client = testCase.replaying("point");
            f = client.getPointForecast(45.3311, -121.6649, MaxHours=24, Members=true);
            testCase.verifyClass(f.point, "struct");
            testCase.verifyClass(f.series.timeseries(1).valid_time, "datetime");
            testCase.verifyEqual(f.members_view, "full");
        end

        function pointCurrent(testCase)
            client = testCase.replaying("pointcurrent");
            c = client.getPointCurrent(45.3311, -121.6649);
            testCase.verifyClass(c.now, "struct");
            testCase.verifyTrue(isfield(c.now, "code") && isfield(c.now, "icon"));
            testCase.verifyClass(c.summary, "struct");
        end

        function snowTrend(testCase)
            client = testCase.replaying("trend");
            t = client.snowTrend("or/mt-hood-meadows");
            testCase.verifyEqual(t.elevation.height, 1639.2);
            testCase.verifyClass(t.grids, "struct");
            days = t.grids(1).runs(1).days;
            testCase.verifyClass(days, "cell");
            first = days{find(~cellfun(@isempty, days), 1)};
            testCase.verifyTrue(isfield(first, "amount") && ~isfield(first, "snow"));
        end
    end
end
