function out = decode(value, desc, geojson)
%DECODE Normalize jsondecode output against a type descriptor (internal).
%   OUT = ensembleweather.internal.decode(VALUE, DESC, GEOJSON) walks VALUE
%   (the output of jsondecode) against the descriptor DESC from schema.json:
%
%   * an object becomes a scalar struct with exactly the spec's fields, in
%     the spec's order, under their SDK names (BEHAVIOR.md 3.0); unknown
%     fields are dropped and absent or null ones are [];
%   * an array of objects becomes an N-by-1 struct array, or a cell array
%     when its items may be null;
%   * strings become string scalars (enums keep the raw string, so an
%     unknown value is kept as sent), timestamps become UTC datetimes;
%   * an array of numbers becomes a column vector with NaN for null, and an
%     array of number arrays a matrix (row i is item i) when rectangular.
%
%   With GEOJSON true the wire names are kept (no renames): the GeoJSON
%   routes pass their bodies through untouched.
%
%   It throws ensembleweather:internal:decode when VALUE does not have the
%   documented shape.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

table = ensembleweather.internal.schemaTable();
out = walk(value, char(desc), table.Objects, geojson, "");
end

function out = walk(value, desc, objects, geojson, path)
if desc(1) == '?'
    desc = desc(2:end);
end
if isNull(value)
    out = [];
    return
end
switch desc(1)
    case 'o'
        out = object(value, desc(3:end), objects, geojson, path);
    case 'a'
        out = list(value, desc(3:end), objects, geojson, path);
    case {'s', 'e'}
        if ~ischar(value)
            fail(path, "a string");
        end
        out = string(value);
    case 't'
        if ~ischar(value)
            fail(path, "a timestamp");
        end
        out = ensembleweather.internal.parseTime(string(value), path);
    case 'n'
        if ~(isnumeric(value) && isscalar(value))
            fail(path, "a number");
        end
        out = double(value);
    case 'b'
        if ~(islogical(value) && isscalar(value))
            fail(path, "a boolean");
        end
        out = value;
    case 'm'
        out = stringMap(value, path);
    otherwise % 'x': raw
        out = value;
end
end

function out = object(value, name, objects, geojson, path)
if ~(isstruct(value) && isscalar(value))
    fail(path, "an object (" + name + ")");
end
entry = objects(name);
n = numel(entry.wire);
values = cell(n, 1);
for i = 1:n
    key = entry.decoded{i};
    if isfield(value, key)
        values{i} = walk(value.(key), entry.type{i}, objects, geojson, ...
            path + "." + entry.wire{i});
    end
end
if geojson
    names = entry.raw;
else
    names = entry.sdk;
end
if n == 0
    out = struct();
else
    out = cell2struct(values, names, 1);
end
end

function out = list(value, item, objects, geojson, path)
nullableItems = item(1) == '?';
kind = item(1 + nullableItems);
switch kind
    case 'n'
        out = numbers(value, path);
    case 'b'
        if islogical(value)
            out = value(:);
        else
            out = cellfun(@(v) walk(v, 'b', objects, geojson, path), cells(value, path));
            out = logical(out(:));
        end
    case {'s', 'e'}
        if isempty(value)
            out = strings(0, 1);
        else
            c = cells(value, path);
            out = strings(numel(c), 1);
            for i = 1:numel(c)
                if isNull(c{i})
                    out(i) = missing;
                elseif ischar(c{i})
                    out(i) = string(c{i});
                else
                    fail(path + "[" + (i - 1) + "]", "a string");
                end
            end
        end
    case 't'
        c = cells(value, path);
        out = datetime(NaN(numel(c), 1), "ConvertFrom", "posixtime", ...
            "TimeZone", "UTC", "Format", ensembleweather.internal.parseTime());
        for i = 1:numel(c)
            if ~isNull(c{i})
                out(i) = walk(c{i}, 't', objects, geojson, path + "[" + (i - 1) + "]");
            end
        end
    case 'a'
        out = nested(value, item(1 + nullableItems:end), objects, geojson, path);
    case 'o'
        name = item(3 + nullableItems:end);
        c = cells(value, path);
        decoded = cell(numel(c), 1);
        for i = 1:numel(c)
            decoded{i} = walk(c{i}, item, objects, geojson, path + "[" + (i - 1) + "]");
        end
        if nullableItems
            out = decoded;
        elseif isempty(decoded)
            out = emptyStructs(objects(name), geojson);
        else
            out = vertcat(decoded{:});
        end
    otherwise
        out = value;
end
end

function out = numbers(value, path)
% A JSON number array, null items as NaN, as a column vector.
if isnumeric(value)
    out = double(value(:));
    return
end
c = cells(value, path);
out = NaN(numel(c), 1);
for i = 1:numel(c)
    v = c{i};
    if isNull(v)
        continue
    elseif isnumeric(v) && isscalar(v)
        out(i) = double(v);
    else
        fail(path + "[" + (i - 1) + "]", "a number");
    end
end
end

function out = nested(value, item, objects, geojson, path)
% An array of arrays: a matrix (row i = item i) when the items are numbers of
% one length, else an N-by-1 cell array of row vectors / decoded items.
if item(3) == 'n' || (item(3) == '?' && item(4) == 'n')
    if isnumeric(value) && ismatrix(value)
        out = double(value);
        return
    end
    c = cells(value, path);
    rows = cell(numel(c), 1);
    for i = 1:numel(c)
        if isNull(c{i})
            rows{i} = zeros(1, 0);
        else
            rows{i} = reshape(numbers(c{i}, path + "[" + (i - 1) + "]"), 1, []);
        end
    end
    lengths = cellfun(@numel, rows);
    if ~isempty(rows) && all(lengths == lengths(1))
        out = vertcat(rows{:});
    else
        out = rows;
    end
    return
end
if isnumeric(value) && isempty(value)
    out = cell(0, 1);
    return
end
c = cells(value, path);
out = cell(numel(c), 1);
for i = 1:numel(c)
    out{i} = walk(c{i}, item, objects, geojson, path + "[" + (i - 1) + "]");
end
end

function c = cells(value, path)
% The items of a decoded JSON array, as a column cell array.
if iscell(value)
    c = value(:);
elseif isstruct(value)
    c = num2cell(value(:));
elseif isnumeric(value) && isempty(value)
    c = cell(0, 1);
elseif isnumeric(value) || islogical(value)
    c = num2cell(value(:));
elseif ischar(value)
    c = {value};
else
    fail(path, "an array");
end
end

function out = emptyStructs(entry, geojson)
if geojson
    names = entry.raw;
else
    names = entry.sdk;
end
out = cell2struct(cell(numel(names), 0), names, 1);
end

function out = stringMap(value, path)
% A JSON object of strings (its keys are data) as a string-to-string dictionary.
if ~(isstruct(value) && isscalar(value))
    fail(path, "an object of strings");
end
keys = string(fieldnames(value));
vals = strings(numel(keys), 1);
for i = 1:numel(keys)
    v = value.(keys(i));
    if ~ischar(v)
        fail(path + "." + keys(i), "a string");
    end
    vals(i) = string(v);
end
out = dictionary(keys, vals);
end

function tf = isNull(value)
tf = isnumeric(value) && isempty(value);
end

function fail(path, what)
if strlength(path) == 0
    path = "the body";
else
    path = extractAfter(path, 1);
end
error("ensembleweather:internal:decode", "%s is not %s", path, what);
end
