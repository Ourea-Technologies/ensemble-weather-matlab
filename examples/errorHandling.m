% ERRORHANDLING Catching errors by identifier or code, and reading the rate-limit state.

client = ensembleweather.Client();

% Coordinates outside the forecast domain (CONUS).
try
    client.getPointForecast(45.0, 10.0);
catch err
    switch err.identifier
        case "ensembleweather:outsideCoverage"
            fprintf("outside coverage: %s\n", err.message);
        case "ensembleweather:permission"  % no Pro key: PRO_REQUIRED comes first
            fprintf("needs Pro: %s\n", err.Code);
        otherwise
            rethrow(err)
    end
end

% A refused coordinate request may name a nearby location that needs no key.
try
    client.getPointForecast(45.33, -121.67);
catch err
    if err.identifier == "ensembleweather:permission" && ~isempty(err.NearestLocation)
        near = err.NearestLocation;
        fprintf("try %s (%s) without a key\n", near.url, near.slug);
    elseif ~startsWith(err.identifier, "ensembleweather:")
        rethrow(err)
    end
end

% Any API error carries the status, the code (verbatim) and a request id.
try
    client.forecast("or/no-such-place");
catch err
    if err.identifier == "ensembleweather:notFound"
        fprintf("%d %s (request id %s)\n", err.Status, err.Code, string(err.RequestId));
        fprintf("see %s\n", string(err.DocUrl));
    elseif err.identifier == "ensembleweather:rateLimited"
        fprintf("rate limited; retry after %g s\n", err.RetryAfter);
    else
        rethrow(err)
    end
end

% Rate-limit state is what the server reported on the last response. It is
% absent on anonymous responses the edge may share between callers.
[~, meta] = client.forecast("or/mt-hood-meadows");
limit = meta.rate_limit;
if isempty(limit)
    disp("rate limit: not reported on this (edge-cacheable) response")
else
    fprintf("rate limit: %d of %d left, resets in %d s\n", limit.remaining, limit.limit, ...
        limit.reset);
end
