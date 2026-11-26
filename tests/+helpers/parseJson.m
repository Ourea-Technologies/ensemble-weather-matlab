function value = parseJson(text)
%PARSEJSON A small JSON reader that keeps object keys exactly (tests only).
%   jsondecode rewrites keys into valid field names ("location.slug" and
%   "Content-Type" do not survive), so the vector runner reads the vector
%   files with this instead. Objects become containers.Map (char keys),
%   arrays 1-by-N cell arrays, strings string scalars, numbers doubles,
%   true/false logicals, and null [].

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

text = char(text);
[value, i] = parseValue(text, skip(text, 1));
i = skip(text, i);
if i <= numel(text)
    error("helpers:json", "trailing text at %d", i);
end
end

function i = skip(text, i)
while i <= numel(text) && any(text(i) == [' ', char(9), char(10), char(13)])
    i = i + 1;
end
end

function [value, i] = parseValue(text, i)
switch text(i)
    case '{'
        value = containers.Map("KeyType", "char", "ValueType", "any");
        i = skip(text, i + 1);
        if text(i) == '}'
            i = i + 1;
            return
        end
        while true
            [key, i] = parseString(text, i);
            i = skip(text, i);
            assert(text(i) == ':', "helpers:json", "expected : at %d", i);
            [item, i] = parseValue(text, skip(text, i + 1));
            value(char(key)) = item;
            i = skip(text, i);
            if text(i) == ','
                i = skip(text, i + 1);
            elseif text(i) == '}'
                i = i + 1;
                return
            else
                error("helpers:json", "expected , or } at %d", i);
            end
        end
    case '['
        value = {};
        i = skip(text, i + 1);
        if text(i) == ']'
            i = i + 1;
            return
        end
        while true
            [item, i] = parseValue(text, i);
            value{end + 1} = item; %#ok<AGROW>
            i = skip(text, i);
            if text(i) == ','
                i = skip(text, i + 1);
            elseif text(i) == ']'
                i = i + 1;
                return
            else
                error("helpers:json", "expected , or ] at %d", i);
            end
        end
    case '"'
        [value, i] = parseString(text, i);
    case 't'
        value = true;
        i = i + 4;
    case 'f'
        value = false;
        i = i + 5;
    case 'n'
        value = [];
        i = i + 4;
    otherwise
        token = regexp(text(i:end), '^-?\d+(\.\d+)?([eE][+-]?\d+)?', "match", "once");
        if isempty(token)
            error("helpers:json", "unexpected %s at %d", text(i), i);
        end
        value = str2double(token);
        i = i + numel(token);
end
end

function [value, i] = parseString(text, i)
assert(text(i) == '"', "helpers:json", "expected a string at %d", i);
i = i + 1;
out = blanks(0);
while text(i) ~= '"'
    c = text(i);
    if c == '\'
        e = text(i + 1);
        switch e
            case 'n', out(end + 1) = char(10); %#ok<AGROW>
            case 't', out(end + 1) = char(9); %#ok<AGROW>
            case 'r', out(end + 1) = char(13); %#ok<AGROW>
            case 'b', out(end + 1) = char(8); %#ok<AGROW>
            case 'f', out(end + 1) = char(12); %#ok<AGROW>
            case 'u'
                out(end + 1) = char(hex2dec(text(i + 2:i + 5))); %#ok<AGROW>
                i = i + 4;
            otherwise, out(end + 1) = e; %#ok<AGROW>
        end
        i = i + 2;
    else
        out(end + 1) = c; %#ok<AGROW>
        i = i + 1;
    end
end
value = string(out);
i = i + 1;
end
