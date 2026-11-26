function seconds = retryAfter(value, now)
%RETRYAFTER Seconds to wait from a Retry-After header, or [] (internal).
%   VALUE is delta-seconds ("3") or an HTTP-date; NOW is the current POSIX
%   time in seconds.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

seconds = [];
if isempty(value)
    return
end
text = strtrim(value);
if ~isempty(regexp(text, "^\d+$", "once"))
    seconds = str2double(text);
    return
end
try
    when = datetime(text, "InputFormat", "eee, dd MMM yyyy HH:mm:ss 'GMT'", ...
        "Locale", "en_US", "TimeZone", "UTC");
catch
    return
end
seconds = max(0, posixtime(when) - now);
end
