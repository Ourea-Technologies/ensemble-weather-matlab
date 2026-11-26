function t = parseTime(text, path)
%PARSETIME Parse an RFC 3339 timestamp into a UTC datetime (internal).
%   T = ensembleweather.internal.parseTime(TEXT) accepts
%   2026-11-25T04:00:00Z, fractional seconds, and a numeric offset such
%   as -08:00, and returns the same instant as a datetime in UTC.
%   F = ensembleweather.internal.parseTime() returns the display format.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

format = "yyyy-MM-dd'T'HH:mm:ss.SSSXXX";
if nargin == 0
    t = "yyyy-MM-dd'T'HH:mm:ssXXX";
    return
end
if nargin < 2
    path = "";
end
parts = regexp(text, ...
    "^(\d{4}-\d{2}-\d{2})[Tt ](\d{2}:\d{2}:\d{2})(\.\d+)?([Zz]|[+-]\d{2}:\d{2})$", ...
    "tokens", "once");
if isempty(parts)
    where = path;
    if strlength(where) > 0
        where = extractAfter(where, 1) + ": ";
    end
    error("ensembleweather:internal:decode", "%s%s is not an RFC 3339 timestamp", ...
        where, text);
end
fraction = parts{3};
if strlength(fraction) == 0
    fraction = ".000";
else
    fraction = extractBefore(fraction + "000", 5);
end
offset = parts{4};
if upper(offset) == "Z"
    offset = "+00:00";
end
t = datetime(parts{1} + "T" + parts{2} + fraction + offset, ...
    "InputFormat", format, "TimeZone", "UTC");
t.Format = "yyyy-MM-dd'T'HH:mm:ssXXX";
end
