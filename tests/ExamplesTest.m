classdef ExamplesTest < matlab.unittest.TestCase
    %EXAMPLESTEST Every example runs, and the real HTTP transport sends canonical URLs.
    %   Both run against tests/stub_server.py (a local stand-in for the API,
    %   started here with python3), never the real API. Without python3 the
    %   tests are filtered, not failed; CI always has it.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Constant)
        Required = ["quickstart", "pointForecast", "chanceOfSnow", "stormTotal", ...
            "searchAndCatalog", "currentAndAlerts", "errorHandling", "units"]
    end

    properties (TestParameter)
        example = ExamplesTest.examples()
        key = struct("anonymous", "", "keyed", "ow_ci_example_key")
    end

    properties (Access = private)
        Root
        Url
        Pid
    end

    methods (Static)
        function names = examples()
            root = fileparts(fileparts(mfilename("fullpath")));
            files = dir(fullfile(root, "examples", "*.m"));
            names = cellstr(erase(string({files.name}), ".m"));
        end
    end

    methods (TestClassSetup)
        function startStub(testCase)
            testCase.Root = fileparts(fileparts(mfilename("fullpath")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture( ...
                fullfile(testCase.Root, "toolbox")));
            [status, ~] = system("python3 --version");
            testCase.assumeEqual(status, 0, "python3 is needed to run the stub server");
            urlFile = string(tempname) + ".url";
            script = fullfile(testCase.Root, "tests", "stub_server.py");
            system(sprintf('python3 "%s" --url-file "%s" > /dev/null 2>&1 &', script, urlFile));
            deadline = tic;
            while ~isfile(urlFile) && toc(deadline) < 20
                pause(0.1);
            end
            testCase.assertTrue(isfile(urlFile), "the stub server did not start");
            parts = split(strtrim(string(fileread(urlFile))), " ");
            testCase.Pid = parts(1);
            testCase.Url = parts(2);
            delete(urlFile);
            testCase.addTeardown(@() system("kill " + testCase.Pid));
        end
    end

    methods (TestMethodSetup)
        function environment(testCase)
            import matlab.unittest.fixtures.EnvironmentVariableFixture
            testCase.applyFixture(EnvironmentVariableFixture("OUREA_BASE_URL", testCase.Url));
            testCase.applyFixture(EnvironmentVariableFixture("OUREA_API_KEY", ""));
            testCase.applyFixture(matlab.unittest.fixtures.SuppressedWarningsFixture( ...
                "ensembleweather:deprecated"));
        end
    end

    methods (Test)
        function everyRequiredExampleExists(testCase)
            testCase.verifyEmpty(setdiff(ExamplesTest.Required, string(ExamplesTest.examples())));
        end

        function exampleRuns(testCase, example, key)
            testCase.applyFixture(matlab.unittest.fixtures.EnvironmentVariableFixture( ...
                "OUREA_API_KEY", key));
            file = fullfile(testCase.Root, "examples", example + ".m");
            output = runScript(file);
            testCase.verifyNotEmpty(strtrim(output), "an example prints what it shows");
            testCase.verifyFalse(contains(output, "ow_ci_example_key"));
        end

        function examplesHaveAHeader(testCase)
            for name = string(ExamplesTest.examples())
                text = fileread(fullfile(testCase.Root, "examples", name + ".m"));
                testCase.verifyTrue(startsWith(text, "% " + upper(name) + " "), name);
            end
        end

        function readmeQuickstartIsTheExample(testCase)
            readme = string(fileread(fullfile(testCase.Root, "README.md"), "Encoding", "UTF-8"));
            blocks = extractBetween(extractAfter(readme, "## Quickstart"), ...
                "```matlab" + newline, "```");
            testCase.assertNotEmpty(blocks, "README has no MATLAB code");
            source = string(fileread(fullfile(testCase.Root, "examples", "quickstart.m"), ...
                "Encoding", "UTF-8"));
            lines = splitlines(source);
            body = join(lines(find(~startsWith(lines, "%"), 1) + 1:end), newline);
            testCase.verifyEqual(blocks(1), body, ...
                "the README quickstart must be examples/quickstart.m (after its header)");
        end

        function pointForecastWithoutKeySaysSo(testCase)
            output = runScript(fullfile(testCase.Root, "examples", "pointForecast.m"));
            testCase.verifySubstring(output, "OUREA_API_KEY");
        end

        function transportSendsTheCanonicalUrl(testCase)
            % matlab.net.http must not re-encode: literal commas and colons,
            % %20 for a space, uppercase hex (BEHAVIOR.md 3.1).
            client = ensembleweather.Client();
            [~, meta] = client.forecast("or/mt-hood-meadows", Sources=["snotel", "asos"], ...
                Prob=[ensembleweather.Chance.atLeast("snowfall", 6, Unit="in"), ...
                ensembleweather.Chance.atMost("temperature", 0)], MaxHours=48);
            sent = ensembleweather.internal.header(meta.headers, "X-Stub-Request");
            testCase.verifyEqual(sent, "/api/v1/locations/or/mt-hood-meadows?max_hours=48" ...
                + "&prob=snowfall:ge:152.40:24h,temperature:le:0.0:24h&sources=asos,snotel");
            [~, meta] = client.search("Mt. Hood & co");
            testCase.verifyEqual(ensembleweather.internal.header(meta.headers, "X-Stub-Request"), ...
                "/api/v1/search/locations?q=Mt.%20Hood%20%26%20co");
            ua = ensembleweather.internal.header(meta.headers, "X-Stub-User-Agent");
            testCase.verifyEqual(ua, client.UserAgent);
            testCase.verifyEqual(meta.status, 200);
        end

        function transportDecodesBodiesAndHeaders(testCase)
            client = ensembleweather.Client(ApiKey="ow_ci_example_key");
            [forecast, meta] = client.forecast("or/mt-hood-meadows");
            testCase.verifyEqual(forecast.location.slug, "mt-hood-meadows");
            testCase.verifyEqual(meta.rate_limit.limit, 60);
            testCase.verifyEqual(client.RateLimit.remaining, 59);
            testCase.verifyError(@() client.forecast("or/no-such-place"), ...
                "ensembleweather:notFound");
        end
    end
end

function output = runScript(file)
% Run an example script in its own workspace and return what it printed.
output = string(evalc("run(""" + file + """)"));
end
