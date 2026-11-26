function usage(message, varargin)
%USAGE Throw a usage error (refused before sending) from the caller (internal).

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

if nargin > 1
    message = sprintf(message, varargin{:});
end
throwAsCaller(ensembleweather.OureaError("usage", message));
end
