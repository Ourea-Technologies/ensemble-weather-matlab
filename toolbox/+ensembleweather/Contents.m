% ensembleweather - Official MATLAB toolbox for the Ourea probabilistic weather API
% Version 0.1.0
%
% Client
%   Client      - a client for the API (forecasts, current conditions, alerts, ...)
%   Pager       - a lazy iterator over a list route (Client.iter* methods)
%
% Asking for probabilities and totals (computed by the server)
%   Chance      - one probability term: P(variable >= or <= threshold) over a window
%   Total       - one window total: the distribution of members' totals
%
% Working with results
%   toTimetable - an hourly series as a timetable of its quantiles
%   interval    - a served quantile pair ([p10 p90] or [p25 p75])
%
% Caching and errors
%   Cache       - the interface of a response store
%   MemoryCache - the default in-memory LRU store
%   OureaError  - the error type (identifiers ensembleweather:<category>)
%
% Documentation: https://docs.oureawx.com/matlab

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.
