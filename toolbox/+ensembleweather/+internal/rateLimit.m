function state = rateLimit(headers)
%RATELIMIT The RateLimit-* headers as a struct, or [] when there are none (internal).
%   Fields: limit, remaining, reset (seconds), policy (the raw header).

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

h = @(name) ensembleweather.internal.header(headers, name);
values = {h("RateLimit-Limit"), h("RateLimit-Remaining"), h("RateLimit-Reset"), ...
    h("RateLimit-Policy")};
if all(cellfun(@isempty, values))
    state = [];
    return
end
state = struct("limit", number(values{1}), "remaining", number(values{2}), ...
    "reset", number(values{3}), "policy", values{4});
end

function n = number(value)
n = [];
if ~isempty(value)
    n = str2double(value);
    if isnan(n)
        n = [];
    end
end
end
