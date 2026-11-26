function out = deprecation(action, operation, headers)
%DEPRECATION Warn once per operation per session about Deprecation/Sunset (internal).
%   ensembleweather.internal.deprecation("check", OPERATION, HEADERS) issues
%   the warning ensembleweather:deprecated the first time OPERATION's
%   response carries a Deprecation or Sunset header, with the
%   Link rel="deprecation" URL (BEHAVIOR.md 11).
%   MESSAGES = ensembleweather.internal.deprecation("emitted") lists the
%   warnings issued so far, and deprecation("reset") forgets them (tests).

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

persistent warned messages
if isempty(warned)
    warned = strings(1, 0);
    messages = strings(1, 0);
end
out = [];
switch action
    case "reset"
        warned = strings(1, 0);
        messages = strings(1, 0);
    case "emitted"
        out = messages;
    case "check"
        dep = ensembleweather.internal.header(headers, "Deprecation");
        sunset = ensembleweather.internal.header(headers, "Sunset");
        if isempty(dep) && isempty(sunset)
            return
        end
        if any(warned == operation)
            return
        end
        warned(end + 1) = operation;
        parts = "The Ourea API has deprecated " + operation;
        if ~isempty(dep)
            parts(end + 1) = "Deprecation: " + dep;
        end
        if ~isempty(sunset)
            parts(end + 1) = "Sunset: " + sunset;
        end
        link = ensembleweather.internal.header(headers, "Link");
        if ~isempty(link)
            url = regexp(link, '<([^>]*)>\s*;[^,]*rel="?deprecation"?', ...
                "tokens", "once", "ignorecase");
            if ~isempty(url)
                parts(end + 1) = "see " + url{1};
            end
        end
        message = join(parts, "; ") + ".";
        messages(end + 1) = message;
        warning("ensembleweather:deprecated", "%s", message);
end
end
