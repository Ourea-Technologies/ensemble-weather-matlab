function bounds = interval(quantiles, low, high)
%INTERVAL A served quantile pair as [low high].
%   B = ensembleweather.interval(Q) is [Q.p10 Q.p90], the 80% range.
%   B = ensembleweather.interval(Q, 25, 75) is [Q.p25 Q.p75], the middle half.
%
%   Only the pairs the server serves are allowed (10-90 and 25-75): any
%   other pair is an ensembleweather:usage error, because the toolbox never
%   interpolates between quantiles. A bound the server did not send is NaN.
%   The median is Q.p50.
%
%   Example:
%     hour = forecast.series.timeseries(1);
%     ensembleweather.interval(hour.ensemble.temperature)   % [p10 p90]

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

arguments
    quantiles
    low = 10
    high = 90
end
if ~(isequal([low high], [10 90]) || isequal([low high], [25 75]))
    ensembleweather.internal.usage( ...
        "only the served pairs 10-90 and 25-75 are available, not %g-%g", low, high);
end
if ~(isstruct(quantiles) && isscalar(quantiles))
    ensembleweather.internal.usage("interval takes one quantiles struct");
end
bounds = [pick(quantiles, "p" + low), pick(quantiles, "p" + high)];
end

function value = pick(q, name)
value = NaN;
if isfield(q, name) && isnumeric(q.(name)) && isscalar(q.(name))
    value = q.(name);
end
end
