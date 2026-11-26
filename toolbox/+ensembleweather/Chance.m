classdef Chance
    %CHANCE One probability term: the chance that a variable crosses a threshold.
    %   The server computes every probability from the full ensemble; a
    %   Chance only describes what to ask for. Pass a list of them to
    %   Client.forecast or Client.getPointForecast as Prob, and read the
    %   answers, in the same order, from the result's probabilities.
    %
    %   c = ensembleweather.Chance.atLeast("snowfall", 6, Unit="in")
    %       % P(0-24 h snowfall >= 6 in)
    %   c = ensembleweather.Chance.atMost("temperature", 32, Unit="degF", ...
    %       Window=[6 18], Aggregation="all")
    %       % P(every hour from 6 h to 18 h is at or below freezing)
    %
    %   Variables: temperature, wind_speed, snow_level, precipitation, snowfall.
    %   Units: mm in degC degF K m ft m/s mph. Without a Unit the threshold
    %   is in the request's units; with one, the toolbox converts it with
    %   exact factors (1 in = 25.4 mm, 1 ft = 0.3048 m, 1 mph = 0.44704 m/s).
    %   Window: an end hour (24 means hours 0-24) or [start end]; at most 360.
    %   Aggregation: "total" (precipitation and snowfall, their only choice),
    %   "any" (the default for the others) or "all".
    %
    %   Chance properties:
    %     Variable, Op, Threshold, Unit, Window, Aggregation
    %
    %   See also ensembleweather.Total, ensembleweather.Client.forecast.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (SetAccess = immutable)
        Variable (1,1) string   % temperature, wind_speed, snow_level, precipitation or snowfall
        Op (1,1) string         % "ge" (at least) or "le" (at most)
        Threshold (1,1) double  % in Unit, or in the request's units when Unit is ""
        Unit (1,1) string       % the threshold's unit, or "" for the request's units
        Window (1,2) double     % [start end] hours from the first served hour
        Aggregation (1,1) string % "total", "any", "all", or "" for the variable's default
    end

    methods
        function obj = Chance(variable, op, threshold, options)
            %CHANCE Build and validate a term. Prefer atLeast / atMost.
            arguments
                variable
                op
                threshold
                options.Unit = ""
                options.Window = 24
                options.Aggregation = ""
            end
            obj.Variable = member("variable", variable, ensembleweather.Chance.Variables);
            obj.Op = member("op", op, ["ge", "le"]);
            if ~(isnumeric(threshold) && isscalar(threshold) && isreal(threshold) ...
                    && isfinite(threshold))
                ensembleweather.internal.usage("threshold must be a finite number");
            end
            obj.Threshold = double(threshold);
            unit = asText("Unit", options.Unit);
            if strlength(unit) > 0
                unit = member("Unit", unit, ensembleweather.Chance.Units);
                if kind(unit) ~= kind(obj.Variable)
                    ensembleweather.internal.usage("%s cannot be given in %s", ...
                        obj.Variable, unit);
                end
            end
            obj.Unit = unit;
            obj.Window = ensembleweather.Chance.parseWindow(options.Window);
            aggregation = asText("Aggregation", options.Aggregation);
            if strlength(aggregation) > 0
                aggregation = member("Aggregation", aggregation, ["total", "any", "all"]);
                amounts = any(obj.Variable == ["precipitation", "snowfall"]);
                if amounts && aggregation ~= "total"
                    ensembleweather.internal.usage( ...
                        "%s supports only aggregation 'total', not '%s'", ...
                        obj.Variable, aggregation);
                elseif ~amounts && aggregation == "total"
                    ensembleweather.internal.usage( ...
                        "%s supports aggregation 'any' or 'all', not 'total'", obj.Variable);
                end
            end
            obj.Aggregation = aggregation;
        end

        function term = wire(obj, units)
            %WIRE The term's canonical wire spelling for a request in UNITS.
            %   This is what the toolbox sends in prob= and what the server
            %   echoes as the result's term.
            arguments
                obj (1,1) ensembleweather.Chance
                units (1,1) string
            end
            value = obj.Threshold;
            target = requestUnit(obj.Variable, units);
            if strlength(obj.Unit) > 0
                value = convert(value, obj.Unit, target);
            end
            threshold = rounded(value, precision(obj.Variable, units));
            term = obj.Variable + ":" + obj.Op + ":" + threshold + ":" ...
                + ensembleweather.Chance.windowText(obj.Window);
            aggregation = obj.effectiveAggregation();
            if aggregation ~= defaultAggregation(obj.Variable)
                term = term + ":" + aggregation;
            end
        end

        function aggregation = effectiveAggregation(obj)
            %EFFECTIVEAGGREGATION The aggregation the server applies.
            aggregation = obj.Aggregation;
            if strlength(aggregation) == 0
                aggregation = defaultAggregation(obj.Variable);
            end
        end
    end

    methods (Static)
        function obj = atLeast(variable, threshold, options)
            %ATLEAST The chance that VARIABLE is at least THRESHOLD ("ge").
            %   c = ensembleweather.Chance.atLeast("snowfall", 6, Unit="in", Window=72)
            arguments
                variable
                threshold
                options.Unit = ""
                options.Window = 24
                options.Aggregation = ""
            end
            obj = ensembleweather.Chance(variable, "ge", threshold, Unit=options.Unit, ...
                Window=options.Window, Aggregation=options.Aggregation);
        end

        function obj = atMost(variable, threshold, options)
            %ATMOST The chance that VARIABLE is at most THRESHOLD ("le").
            %   c = ensembleweather.Chance.atMost("temperature", 0, Unit="degC")
            arguments
                variable
                threshold
                options.Unit = ""
                options.Window = 24
                options.Aggregation = ""
            end
            obj = ensembleweather.Chance(variable, "le", threshold, Unit=options.Unit, ...
                Window=options.Window, Aggregation=options.Aggregation);
        end
    end

    properties (Constant, Hidden)
        Variables = ["temperature", "wind_speed", "snow_level", "precipitation", "snowfall"]
        Units = ["mm", "in", "degC", "degF", "K", "m", "ft", "m/s", "mph"]
        MaxWindowHours = 360
    end

    methods (Static, Hidden)
        function window = parseWindow(value)
            %PARSEWINDOW Validate a window: an end hour or [start end].
            if ~(isnumeric(value) && isreal(value) && any(numel(value) == [1 2]) ...
                    && all(isfinite(value)) && all(value == fix(value)))
                ensembleweather.internal.usage( ...
                    "a window is an end hour (24) or [start end] in whole hours");
            end
            if isscalar(value)
                window = [0 double(value)];
            else
                window = double(reshape(value, 1, 2));
            end
            if ~(window(1) >= 0 && window(1) < window(2) ...
                    && window(2) <= ensembleweather.Chance.MaxWindowHours)
                ensembleweather.internal.usage( ...
                    "a window must satisfy 0 <= start < end <= %d, got %d-%d h", ...
                    ensembleweather.Chance.MaxWindowHours, window(1), window(2));
            end
        end

        function text = windowText(window)
            %WINDOWTEXT The wire form: "24h", or "6-18h" when it does not start at 0.
            if window(1) == 0
                text = sprintf("%dh", window(2));
            else
                text = sprintf("%d-%dh", window(1), window(2));
            end
        end
    end
end

function value = member(what, value, allowed)
value = asText(what, value);
if ~any(value == allowed)
    ensembleweather.internal.usage("'%s' is not a valid %s; expected one of %s", ...
        value, what, join(allowed, ", "));
end
end

function value = asText(what, value)
if ischar(value) && (isrow(value) || isempty(value))
    value = string(value);
end
if ~(isstring(value) && isscalar(value) && ~ismissing(value))
    ensembleweather.internal.usage("%s must be text", what);
end
end

function k = kind(name)
switch name
    case {"mm", "in", "precipitation", "snowfall"}
        k = "depth";
    case {"degC", "degF", "K", "temperature"}
        k = "temperature";
    case {"m", "ft", "snow_level"}
        k = "height";
    otherwise % m/s, mph, wind_speed
        k = "speed";
end
end

function unit = requestUnit(variable, units)
% The unit the server reads VARIABLE's thresholds in, for UNITS.
imperial = units == "imperial";
switch kind(variable)
    case "depth"
        if imperial, unit = "in"; else, unit = "mm"; end
    case "temperature"
        if imperial
            unit = "degF";
        elseif units == "kelvin"
            unit = "K";
        else
            unit = "degC";
        end
    case "height"
        if imperial, unit = "ft"; else, unit = "m"; end
    otherwise
        if imperial, unit = "mph"; else, unit = "m/s"; end
end
end

function value = convert(value, source, target)
% Convert a caller's threshold between two units of one kind (exact factors).
if source == target
    return
end
if kind(source) == "temperature"
    celsius = value;
    if source == "degF"
        celsius = (value - 32) * 5 / 9;
    elseif source == "K"
        celsius = value - 273.15;
    end
    if target == "degF"
        value = celsius * 9 / 5 + 32;
    elseif target == "K"
        value = celsius + 273.15;
    else
        value = celsius;
    end
    return
end
value = value * toMetric(source) / toMetric(target);
end

function f = toMetric(unit)
switch unit
    case "in", f = 25.4;
    case "ft", f = 0.3048;
    case "mph", f = 0.44704;
    otherwise, f = 1;
end
end

function d = precision(variable, units)
% The number of decimals the server serves VARIABLE at (BEHAVIOR.md 4).
if any(variable == ["precipitation", "snowfall"])
    if units == "imperial", d = 3; else, d = 2; end
elseif variable == "snow_level"
    d = 0;
else
    d = 1;
end
end

function out = rounded(value, decimals)
% Round half away from zero on value * 10^d in doubles, then print d decimals.
% MATLAB's round is half away from zero: 0.0625 at 3 is 0.063, and 1.005 at
% 2 is 1.00 because 1.005 * 100 is 100.4999... A negative zero prints as 0.
whole = round(value * 10^decimals);
if whole == 0
    whole = 0;
end
digits = sprintf("%d", abs(whole));
if decimals == 0
    out = digits;
else
    digits = pad(digits, decimals + 1, "left", "0");
    out = extractBefore(digits, strlength(digits) - decimals + 1) + "." ...
        + extractAfter(digits, strlength(digits) - decimals);
end
if whole < 0
    out = "-" + out;
end
end

function a = defaultAggregation(variable)
if any(variable == ["precipitation", "snowfall"])
    a = "total";
else
    a = "any";
end
end
