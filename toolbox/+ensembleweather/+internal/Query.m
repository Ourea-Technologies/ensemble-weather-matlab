classdef Query < handle
    %QUERY Collects a request's parameters in canonical form (internal).
    %   BEHAVIOR.md 3.1: a parameter the caller did not set, or set to its
    %   default, is omitted; parameters are sorted by name and appear once;
    %   a comma list is sorted, de-duplicated, each item percent-encoded and
    %   joined by a literal comma; other values are RFC 3986 encoded; prob,
    %   totals, near and bbox are built by the toolbox and sent as they are.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (Access = private)
        Names (1,:) string = strings(1, 0)
        Values (1,:) string = strings(1, 0)
    end

    methods
        function add(obj, name, value, default)
            %ADD Add NAME=VALUE unless VALUE is [] or equals DEFAULT.
            if isempty(value)
                return
            end
            text = ensembleweather.internal.Query.format(value, name);
            if nargin > 3 && text == ensembleweather.internal.Query.format(default, name)
                return
            end
            obj.put(name, ensembleweather.internal.encode(text));
        end

        function addList(obj, name, values)
            %ADDLIST Add a comma list (sorted, unique, literal commas).
            if isempty(values)
                return
            end
            values = ensembleweather.internal.Query.texts(values, name);
            items = unique(values);  % sorted, de-duplicated
            encoded = strings(size(items));
            for i = 1:numel(items)
                encoded(i) = ensembleweather.internal.encode(items(i));
            end
            obj.put(name, join(encoded, ","));
        end

        function addRaw(obj, name, value)
            %ADDRAW Add a value the toolbox built itself, sent unencoded.
            if strlength(value) > 0
                obj.put(name, value);
            end
        end

        function text = render(obj)
            %RENDER The query string, without "?", in canonical order.
            if isempty(obj.Names)
                text = "";
                return
            end
            [names, order] = sort(obj.Names);
            text = join(names + "=" + obj.Values(order), "&");
        end
    end

    methods (Access = private)
        function put(obj, name, value)
            name = string(name);
            existing = find(obj.Names == name, 1);
            if isempty(existing)
                obj.Names(end + 1) = name;
                obj.Values(end + 1) = value;
            else
                obj.Values(existing) = value;
            end
        end
    end

    methods (Static)
        function text = format(value, name)
            %FORMAT One query value as text (before percent-encoding).
            if islogical(value) && isscalar(value)
                if value
                    text = "true";
                else
                    text = "false";
                end
            elseif isnumeric(value) && isscalar(value)
                text = ensembleweather.internal.formatNumber(value);
            elseif isdatetime(value) && isscalar(value)
                if isempty(value.TimeZone)
                    ensembleweather.internal.usage( ...
                        "%s: a datetime must have a TimeZone (for example ""UTC"")", name);
                end
                value.TimeZone = "UTC";
                text = string(value, "yyyy-MM-dd'T'HH:mm:ss'Z'");
            elseif (isstring(value) && isscalar(value)) || (ischar(value) && isrow(value))
                text = string(value);
                if strlength(text) == 0
                    ensembleweather.internal.usage("%s must not be empty", name);
                end
            else
                ensembleweather.internal.usage("%s takes one value, got a %s", ...
                    name, class(value));
            end
        end

        function values = texts(values, name)
            %TEXTS A string list from a string array, char or cell of text.
            if ischar(values)
                values = string(values);
            elseif iscellstr(values)
                values = string(values);
            elseif ~isstring(values)
                ensembleweather.internal.usage("%s takes a list of strings", name);
            end
            values = reshape(values, 1, []);
            if any(ismissing(values)) || any(strlength(values) == 0)
                ensembleweather.internal.usage("%s takes non-empty strings", name);
            end
        end
    end
end
