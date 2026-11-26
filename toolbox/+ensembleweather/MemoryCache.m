classdef MemoryCache < ensembleweather.Cache
    %MEMORYCACHE An in-memory LRU response store, bounded by entries and bytes.
    %   cache = ensembleweather.MemoryCache()              % 256 entries, 32 MiB
    %   cache = ensembleweather.MemoryCache(MaxEntries=64, MaxBytes=8*2^20)
    %
    %   The client's default cache. The least recently used entry goes first
    %   when either bound would be passed; an entry larger than MaxBytes is
    %   never stored.
    %
    %   See also ensembleweather.Cache.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (SetAccess = immutable)
        MaxEntries (1,1) double  % the most entries kept
        MaxBytes (1,1) double    % the most body bytes kept, in all
    end

    properties (Dependent)
        Count      % the number of entries
        SizeBytes  % the body bytes held
    end

    properties (Access = private)
        Keys (1,:) string = strings(1, 0)  % least recently used first
        Entries (1,:) cell = {}
        Sizes (1,:) double = zeros(1, 0)
    end

    methods
        function obj = MemoryCache(options)
            %MEMORYCACHE Create an empty cache.
            arguments
                options.MaxEntries (1,1) double {mustBePositive, mustBeInteger} = 256
                options.MaxBytes (1,1) double {mustBePositive} = 32 * 1024 * 1024
            end
            obj.MaxEntries = options.MaxEntries;
            obj.MaxBytes = options.MaxBytes;
        end

        function entry = get(obj, key)
            %GET The entry for KEY (marked most recently used), or [].
            entry = [];
            i = find(obj.Keys == key, 1);
            if isempty(i)
                return
            end
            entry = obj.Entries{i};
            obj.touch(i);
        end

        function set(obj, key, entry)
            %SET Store ENTRY under KEY, evicting the least recently used.
            obj.remove(key);
            bytes = numel(entry.body);
            if bytes > obj.MaxBytes
                return
            end
            obj.Keys(end + 1) = key;
            obj.Entries{end + 1} = entry;
            obj.Sizes(end + 1) = bytes;
            while numel(obj.Keys) > obj.MaxEntries || sum(obj.Sizes) > obj.MaxBytes
                obj.Keys(1) = [];
                obj.Entries(1) = [];
                obj.Sizes(1) = [];
            end
        end

        function remove(obj, key)
            %REMOVE Forget KEY.
            i = find(obj.Keys == key, 1);
            if ~isempty(i)
                obj.Keys(i) = [];
                obj.Entries(i) = [];
                obj.Sizes(i) = [];
            end
        end

        function n = get.Count(obj)
            n = numel(obj.Keys);
        end

        function n = get.SizeBytes(obj)
            n = sum(obj.Sizes);
        end
    end

    methods (Access = private)
        function touch(obj, i)
            order = [1:i - 1, i + 1:numel(obj.Keys), i];
            obj.Keys = obj.Keys(order);
            obj.Entries = obj.Entries(order);
            obj.Sizes = obj.Sizes(order);
        end
    end
end
