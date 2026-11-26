function ua = userAgent(product)
%USERAGENT The toolbox's User-Agent, optionally followed by the app's token (internal).
%   ensemble-weather-matlab/<version> (MATLAB/<release>), e.g.
%   "ensemble-weather-matlab/0.1.0 (MATLAB/R2024b)". It never carries user data.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

ua = "ensemble-weather-matlab/" + ensembleweather.Client.Version ...
    + " (MATLAB/R" + string(version("-release")) + ")";
if nargin > 0 && strlength(product) > 0
    ua = ua + " " + product;
end
end
