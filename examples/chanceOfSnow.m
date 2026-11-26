% CHANCEOFSNOW Several probability terms in one call, each with its window and members.
%   The server computes every probability from the full ensemble; the
%   toolbox only asks. Answers come back in the order you asked.

terms = [
    ensembleweather.Chance.atLeast("snowfall", 6, Unit="in")              % the next 24 h
    ensembleweather.Chance.atLeast("snowfall", 12, Unit="in", Window=72)  % the next 72 h
    ensembleweather.Chance.atMost("temperature", 32, Unit="degF", Window=[6 18], ...
        Aggregation="all")
    ensembleweather.Chance.atLeast("wind_speed", 15, Unit="m/s", Window=[12 36])
    ];
client = ensembleweather.Client();
forecast = client.forecast("or/mt-hood-meadows", Prob=terms);

for r = reshape(forecast.probabilities, 1, [])
    if isempty(r.value)
        chance = "n/a (" + r.null_reason + ")";
    else
        chance = sprintf("%.0f%%", 100 * r.value);
    end
    fprintf("P(%s %s %g (%s units), %d-%d h, %s) = %s from %d members\n", r.variable, ...
        r.op, r.threshold, forecast.units, r.window_start_hours, r.window_end_hours, ...
        r.aggregation, chance, r.members);
end
