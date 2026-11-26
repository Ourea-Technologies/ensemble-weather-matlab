function out = encode(value)
%ENCODE Percent-encode one path segment or query value (internal).
%   OUT = ensembleweather.internal.encode(VALUE) encodes VALUE's UTF-8 bytes
%   with RFC 3986 rules: A-Z a-z 0-9 - . _ ~ as they are, every other byte
%   as %XX in uppercase hex (a space is %20, never +).

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

bytes = unicode2native(char(value), "UTF-8");
keep = (bytes >= 'A' & bytes <= 'Z') | (bytes >= 'a' & bytes <= 'z') | ...
    (bytes >= '0' & bytes <= '9') | bytes == '-' | bytes == '.' | ...
    bytes == '_' | bytes == '~';
parts = cell(1, numel(bytes));
for i = 1:numel(bytes)
    if keep(i)
        parts{i} = char(bytes(i));
    else
        parts{i} = sprintf('%%%02X', bytes(i));
    end
end
out = string([parts{:}]);
if isempty(bytes)
    out = "";
end
end
