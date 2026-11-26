function value = header(headers, name)
%HEADER A response header's value by case-insensitive name, or [] (internal).
%   HEADERS is an N-by-2 string array of names and values; the last
%   matching header wins.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

value = [];
if isempty(headers)
    return
end
match = find(strcmpi(headers(:, 1), name), 1, "last");
if ~isempty(match)
    value = headers(match, 2);
end
end
