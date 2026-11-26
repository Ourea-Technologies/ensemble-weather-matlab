function [wire, terms] = probQuery(chances, units)
%PROBQUERY The canonical prob= value and each caller term's spelling (internal).
%   [WIRE, TERMS] = ensembleweather.internal.probQuery(CHANCES, UNITS):
%   WIRE is the de-duplicated terms sorted by variable, op (ge before le),
%   window start, window end, aggregation (total, any, all) and threshold,
%   joined by literal commas (BEHAVIOR.md 4); TERMS(i) is CHANCES(i)'s own
%   canonical spelling, which the server echoes as the result's term.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

n = numel(chances);
terms = strings(1, n);
keys = cell(n, 1);
for i = 1:n
    c = chances(i);
    terms(i) = c.wire(units);
    parts = split(terms(i), ":");
    keys{i} = {c.Variable, find(c.Op == ["ge", "le"]), c.Window(1), c.Window(2), ...
        find(c.effectiveAggregation() == ["total", "any", "all"]), str2double(parts(3))};
end
[distinct, first] = unique(terms, "stable");
order = 1:numel(distinct);
uniqueKeys = keys(first);
% Insertion sort with the canonical comparator (a handful of terms).
for i = 2:numel(order)
    j = i;
    while j > 1 && before(uniqueKeys{order(j)}, uniqueKeys{order(j - 1)})
        order([j - 1, j]) = order([j, j - 1]);
        j = j - 1;
    end
end
if isempty(distinct)
    wire = "";
else
    wire = join(distinct(order), ",");
end
end

function tf = before(a, b)
% Whether key A sorts strictly before key B.
tf = false;
if a{1} ~= b{1}
    tf = a{1} < b{1};
    return
end
for k = 2:6
    if a{k} ~= b{k}
        tf = a{k} < b{k};
        return
    end
end
end
