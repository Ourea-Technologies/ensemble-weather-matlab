function table = schemaTable()
%SCHEMATABLE The decoding table generated from the pinned spec (internal).
%   T = ensembleweather.internal.schemaTable() returns a struct with
%   containers.Map fields Objects, Enums and Operations, loaded once per
%   session from schema.json (written by scripts/gen_schema.py).

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

persistent cached
if isempty(cached)
    file = fullfile(fileparts(mfilename("fullpath")), "schema.json");
    raw = jsondecode(fileread(file));
    objects = containers.Map("KeyType", "char", "ValueType", "any");
    for i = 1:numel(raw.objects)
        o = raw.objects(i);
        wire = toCell(o.wire);
        sdk = toCell(o.sdk);
        entry.wire = wire;
        % jsondecode stores each key under matlab.lang.makeValidName(key).
        entry.decoded = cellfun(@(w) matlab.lang.makeValidName(w), wire, ...
            "UniformOutput", false);
        entry.sdk = sdk;
        % GeoJSON keeps the wire names (only a MATLAB keyword is escaped).
        entry.raw = cellfun(@escapeKeyword, wire, "UniformOutput", false);
        entry.type = toCell(o.type);
        objects(o.name) = entry;
    end
    enums = containers.Map("KeyType", "char", "ValueType", "any");
    for i = 1:numel(raw.enums)
        enums(raw.enums(i).name) = string(raw.enums(i).values);
    end
    operations = containers.Map("KeyType", "char", "ValueType", "any");
    for i = 1:numel(raw.operations)
        op = raw.operations(i);
        operations(op.id) = struct("path", string(op.path), "type", op.type, ...
            "geojson", logical(op.geojson));
    end
    renames = raw.renames;
    cached = struct("Spec", string(raw.spec), "Objects", objects, ...
        "Enums", enums, "Operations", operations, "Renames", renames);
end
table = cached;
end

function name = escapeKeyword(name)
if iskeyword(name)
    name = [name '_'];
end
end

function c = toCell(x)
if isempty(x)
    c = {};
else
    c = reshape(cellstr(x), 1, []);
end
end
