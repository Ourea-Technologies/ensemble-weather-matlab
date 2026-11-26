classdef Total
    %TOTAL One window total: the distribution of each member's total over a window.
    %   t = ensembleweather.Total("snowfall", 72)        % hours 0-72
    %   t = ensembleweather.Total("precipitation", [24 48])
    %
    %   Pass a list of them to Client.forecast as Totals and read the answers,
    %   in the same order, from the result's window_totals: each has the
    %   quantiles of the members' totals over the window. This is the only
    %   storm total the toolbox offers. Never add up hourly quantiles
    %   instead: the sum of per-hour medians is not the median total.
    %
    %   See also ensembleweather.Chance.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (SetAccess = immutable)
        Variable (1,1) string  % "precipitation" or "snowfall"
        Window (1,2) double    % [start end] hours from the first served hour
    end

    methods
        function obj = Total(variable, window)
            %TOTAL Build and validate a window-total request.
            arguments
                variable
                window = 24
            end
            if ischar(variable)
                variable = string(variable);
            end
            if ~(isstring(variable) && isscalar(variable) ...
                    && any(variable == ["precipitation", "snowfall"]))
                ensembleweather.internal.usage( ...
                    "a total's variable is 'precipitation' or 'snowfall'");
            end
            obj.Variable = variable;
            obj.Window = ensembleweather.Chance.parseWindow(window);
        end

        function term = wire(obj)
            %WIRE The canonical wire spelling ("snowfall:72h"), echoed as the result's term.
            term = obj.Variable + ":" + ensembleweather.Chance.windowText(obj.Window);
        end
    end
end
