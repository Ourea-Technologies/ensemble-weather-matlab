classdef Pager < handle
    %PAGER A lazy iterator over a list route's items, following next_cursor.
    %   The client's iter* methods return a Pager. It fetches a page only
    %   when it needs the next item, and stops when next_cursor is null.
    %
    %     pages = client.iterCatalogLocations(Type="ski_area");
    %     while pages.hasNext()
    %         place = pages.next();
    %         disp(place.name)
    %     end
    %
    %     everything = client.iterExplore("snow_5d").collect();  % N-by-1 struct
    %
    %   Pager methods:
    %     hasNext - whether another item is available (may fetch a page)
    %     next    - the next item (a struct)
    %     collect - every remaining item, as an N-by-1 struct array
    %
    %   Pager properties:
    %     Pages   - the number of pages fetched so far

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (SetAccess = private)
        Pages (1,1) double = 0  % pages fetched so far
    end

    properties (Access = private)
        Fetch            % @(cursor) page struct; cursor is [] for the first page
        Buffer = []      % items of the current page not yet returned
        Position = 0
        Cursor = []
        Done = false
    end

    methods
        function obj = Pager(fetch)
            %PAGER Wrap FETCH, a function of the cursor that returns one page.
            obj.Fetch = fetch;
        end

        function tf = hasNext(obj)
            %HASNEXT Whether another item is available (may fetch a page).
            while obj.Position >= numel(obj.Buffer)
                if obj.Done
                    tf = false;
                    return
                end
                page = obj.Fetch(obj.Cursor);
                obj.Pages = obj.Pages + 1;
                obj.Buffer = page.items;
                obj.Position = 0;
                obj.Cursor = page.next_cursor;
                if isempty(obj.Cursor) || strlength(obj.Cursor) == 0
                    obj.Done = true;
                end
            end
            tf = true;
        end

        function item = next(obj)
            %NEXT The next item. Throws ensembleweather:usage at the end.
            if ~obj.hasNext()
                ensembleweather.internal.usage("the iterator has no more items");
            end
            obj.Position = obj.Position + 1;
            item = obj.Buffer(obj.Position);
        end

        function items = collect(obj)
            %COLLECT Every remaining item, as an N-by-1 struct array.
            parts = {};
            while obj.hasNext()
                parts{end + 1, 1} = obj.Buffer(obj.Position + 1:end); %#ok<AGROW>
                obj.Position = numel(obj.Buffer);
            end
            if isempty(parts)
                items = obj.Buffer([]);
            else
                items = vertcat(parts{:});
            end
        end
    end
end
