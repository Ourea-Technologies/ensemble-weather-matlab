classdef Replay < handle
    %REPLAY A mock transport: answers with canned responses in order, records requests.
    %   replay = helpers.Replay(responses, bodiesFolder);
    %   client = ensembleweather.Client(Transport=@replay.send);
    %
    %   RESPONSES is a cell array of containers.Map (a vector's "responses")
    %   or of structs with fields status, headers (N-by-2 string) and body.

    %   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

    properties
        Responses cell = {}
        Requests cell = {}
        Folder string = ""
        Delays (1,:) double = zeros(1, 0)
    end

    methods
        function obj = Replay(responses, folder)
            if nargin > 0
                obj.Responses = responses;
            end
            if nargin > 1
                obj.Folder = folder;
            end
        end

        function add(obj, status, headers, body)
            %ADD Queue one response (HEADERS N-by-2 string, BODY text).
            if nargin < 3 || isempty(headers)
                headers = strings(0, 2);
            end
            if nargin < 4
                body = "";
            end
            obj.Responses{end + 1} = struct("status", status, "headers", headers, "body", body);
        end

        function sleep(obj, seconds)
            %SLEEP Record a retry delay instead of waiting.
            obj.Delays(end + 1) = seconds;
        end

        function response = send(obj, request)
            obj.Requests{end + 1} = request;
            if isempty(obj.Responses)
                error("helpers:replay", "unexpected request #%d: %s", ...
                    numel(obj.Requests), request.url);
            end
            spec = obj.Responses{1};
            obj.Responses(1) = [];
            if isstruct(spec)
                response = struct("status", spec.status, "headers", spec.headers, ...
                    "body", unicode2native(char(spec.body), "UTF-8"));
                return
            end
            headers = strings(0, 2);
            if isKey(spec, "headers")
                h = spec("headers");
                names = keys(h);
                for k = 1:numel(names)
                    headers(end + 1, :) = [string(names{k}), h(names{k})]; %#ok<AGROW>
                end
            end
            body = "";
            if isKey(spec, "body_file")
                body = string(fileread(fullfile(obj.Folder, spec("body_file")), ...
                    "Encoding", "UTF-8"));
            elseif isKey(spec, "body")
                body = spec("body");
            end
            response = struct("status", spec("status"), "headers", headers, ...
                "body", unicode2native(char(body), "UTF-8"));
        end
    end
end
