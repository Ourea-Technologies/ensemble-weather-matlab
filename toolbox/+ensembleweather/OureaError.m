classdef OureaError < MException
    %OUREAERROR The one error type the toolbox throws.
    %   Every error the toolbox throws is an ensembleweather.OureaError. Its
    %   identifier names its category, so a catch block can test it:
    %
    %     try
    %         client.getPointForecast(45.0, 10.0);
    %     catch err
    %         if err.identifier == "ensembleweather:outsideCoverage"
    %             disp(err.Code)   % "OUTSIDE_COVERAGE"
    %         else
    %             rethrow(err)
    %         end
    %     end
    %
    %   Identifier                         Category (BEHAVIOR.md 8)
    %   ensembleweather:authentication     authentication (401)
    %   ensembleweather:permission         permission (403: PRO_REQUIRED, PLUS_REQUIRED)
    %   ensembleweather:notFound           not_found (404, 410)
    %   ensembleweather:invalidRequest     invalid_request (400)
    %   ensembleweather:outsideCoverage    outside_coverage (OUTSIDE_COVERAGE)
    %   ensembleweather:rateLimited        rate_limited (429)
    %   ensembleweather:unavailable        unavailable (5xx)
    %   ensembleweather:api                any other HTTP error status
    %   ensembleweather:connection         no response: DNS, TLS, reset, timeout
    %   ensembleweather:usage              refused before sending (bad argument)
    %   ensembleweather:unexpectedResponse a 2xx body that is not the documented shape
    %
    %   The API key never appears in an error's message or properties.
    %
    %   OureaError properties:
    %     Category        - the category above, in snake_case ("not_found")
    %     Status          - the HTTP status, or [] when there was no response
    %     Code            - the API's error code, verbatim (even an unknown one), or []
    %     RequestId       - the request id, for support (the body's, else X-Request-Id)
    %     DocUrl          - the documentation of the code, when the body names it
    %     Param           - the query parameter a 400 is about, when it names one
    %     RetryAfter      - seconds the server asked to wait (Retry-After), or []
    %     RateLimit       - the rate-limit state the response reported, or []
    %     NearestLocation - on PRO_REQUIRED at coordinates, the nearest named
    %                       location that answers without a key, or []

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties (SetAccess = private)
        Category
        Status = []
        Code = []
        RequestId = []
        DocUrl = []
        Param = []
        RetryAfter = []
        RateLimit = []
        NearestLocation = []
    end

    methods
        function obj = OureaError(category, message, details)
            %OUREAERROR Create an error of CATEGORY with MESSAGE.
            %   DETAILS is an optional struct whose fields (Status, Code,
            %   RequestId, DocUrl, Param, RetryAfter, RateLimit,
            %   NearestLocation) are copied onto the error.
            arguments
                category (1,1) string
                message (1,1) string
                details (1,1) struct = struct()
            end
            id = "ensembleweather:" + identifierPart(category);
            obj@MException(char(id), '%s', char(message));
            obj.Category = category;
            names = fieldnames(details);
            for i = 1:numel(names)
                obj.(names{i}) = details.(names{i});
            end
        end
    end
end

function part = identifierPart(category)
% snake_case category to the identifier's camelCase ("not_found" -> "notFound").
words = split(category, "_");
for i = 2:numel(words)
    words(i) = upper(extractBefore(words(i), 2)) + extractAfter(words(i), 1);
end
part = join(words, "");
end
