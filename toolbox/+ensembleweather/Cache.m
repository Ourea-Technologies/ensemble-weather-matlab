classdef (Abstract) Cache < handle
    %CACHE The interface of a response store for the client's ETag cache.
    %   The client keeps a local ETag cache, on by default (an in-memory
    %   ensembleweather.MemoryCache of 256 entries / 32 MiB). To share one
    %   across clients, or to back it with your own store, subclass Cache
    %   and pass an instance as the client's Cache option:
    %
    %     client = ensembleweather.Client(Cache=myStore);
    %
    %   Keys are the request URL plus a hash of the API key (never the key
    %   itself), so entries for different keys never mix. An entry is a
    %   struct with fields body (char), etag (string or ""), headers (N-by-2
    %   string), storedAt (POSIX seconds) and maxAge (seconds, or NaN).
    %
    %   Cache methods:
    %     get    - the entry for a key, or [] when there is none
    %     set    - store an entry under a key
    %     remove - forget a key
    %
    %   See also ensembleweather.MemoryCache.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    methods (Abstract)
        entry = get(obj, key)
        set(obj, key, entry)
        remove(obj, key)
    end
end
