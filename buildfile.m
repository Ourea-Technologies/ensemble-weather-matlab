function plan = buildfile
%BUILDFILE The toolbox's build: buildtool check | test | package.
%   buildtool          % check and test (the default tasks)
%   buildtool check    % Code Analyzer with zero issues, and no eval/evalin/evalc/assignin
%   buildtool test     % every test in tests/ (unit, the 58 shared vectors, spec
%                      % drift, and the examples against the local stub server)
%   buildtool package  % check, test, then release/ensemble-weather-matlab-<version>.mltbx
%
%   Needs MATLAB R2023b or later. The example tests also need python3, for
%   tests/stub_server.py.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

import matlab.buildtool.tasks.TestTask

plan = buildplan(localfunctions);

plan("check").Dependencies = ["analyze", "evalGate"];

plan("test") = TestTask("tests", IncludeSubfolders=true);
plan("test").Description = "Unit tests, the shared vectors, spec drift and the examples";

plan("package").Dependencies = ["check", "test"];

plan.DefaultTasks = ["check", "test"];
end

function checkTask(~)
% Static checks: Code Analyzer and the eval gate.
end

function analyzeTask(context)
% Code Analyzer: zero errors and zero warnings in every MATLAB file.
root = context.Plan.RootFolder;
targets = fullfile(root, ["toolbox", "tests", "examples", "scripts", "buildfile.m"]);
issues = codeIssues(targets, IncludeSubfolders=true);
found = issues.Issues;
for i = 1:height(found)
    fprintf("%s:%d: [%s] %s %s\n", string(found.FullFilename(i)), found.LineStart(i), ...
        string(found.Severity(i)), string(found.CheckID(i)), string(found.Description(i)));
end
fprintf("analyze: %d files, %d issues\n", numel(issues.Files), height(found));
assert(height(found) == 0, "analyze:issues", "Code Analyzer found %d issues", height(found));
end

function evalGateTask(context)
% No eval, evalin, evalc or assignin anywhere in the shipped toolbox (SDK-STANDARD "Security").
root = context.Plan.RootFolder;
files = dir(fullfile(root, "toolbox", "**", "*.m"));
found = strings(0, 1);
for i = 1:numel(files)
    file = fullfile(files(i).folder, files(i).name);
    lines = splitlines(string(fileread(file)));
    for k = 1:numel(lines)
        code = extractBefore(lines(k) + "%", "%");
        if ~isempty(regexp(code, "\<(eval|evalin|evalc|assignin)\s*\(", "once"))
            found(end + 1) = sprintf("%s:%d: %s", file, k, strtrim(lines(k))); %#ok<AGROW>
        end
    end
end
assert(isempty(found), "evalGate:found", "eval-family calls in the toolbox:\n%s", ...
    join(found, newline));
fprintf("evalGate: %d toolbox files, no eval/evalin/evalc/assignin\n", numel(files));
end

function packageTask(context)
% Package toolbox/ as release/ensemble-weather-matlab-<version>.mltbx.
root = context.Plan.RootFolder;
addpath(fullfile(root, "toolbox"));
version = ensembleweather.Client.Version;
% A fixed identifier: every release of this toolbox shares it, so the
% Add-On Manager upgrades in place.
identifier = "8b0f5d3e-6c1a-4e57-9b8e-0d6f2a7c4e19";
options = matlab.addons.toolbox.ToolboxOptions(fullfile(root, "toolbox"), identifier);
options.ToolboxName = "Ourea Ensemble Weather";
options.ToolboxVersion = version;
options.Summary = "Official MATLAB toolbox for the Ourea probabilistic weather API.";
options.Description = "Ensemble weather forecasts from Ourea (https://oureawx.com): " ...
    + "quantiles and exceedance probabilities computed by the server from the full " ...
    + "ensemble, as MATLAB structs and timetables. Forecasts, current conditions, " ...
    + "alerts, search, explore, season totals, snowpack and avalanche zones. " ...
    + "Keywords: ourea, weather, forecast, ensemble, probabilistic.";
options.AuthorName = "Ourea Technologies";
options.AuthorCompany = "Ourea Technologies";
options.MinimumMatlabRelease = "R2023b";
options.MaximumMatlabRelease = "";
output = fullfile(root, "release");
if ~isfolder(output)
    mkdir(output);
end
options.OutputFile = fullfile(output, "ensemble-weather-matlab-" + version + ".mltbx");
matlab.addons.toolbox.packageToolbox(options);
fprintf("package: %s\n", options.OutputFile);
end
