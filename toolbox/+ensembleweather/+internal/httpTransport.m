function response = httpTransport(request, timeout)
%HTTPTRANSPORT Send one GET with matlab.net.http and return the raw response (internal).
%   RESPONSE = ensembleweather.internal.httpTransport(REQUEST, TIMEOUT)
%   sends REQUEST (a struct with url, a string, and headers, an N-by-2
%   string array) without following redirects (the client follows them
%   itself, so it can drop the key on another host), with TLS verification
%   on (MATLAB's default; there is no option to turn it off), and returns a
%   struct with status (double), headers (N-by-2 string) and body (uint8,
%   decompressed).
%
%   The URL is sent exactly as built (matlab.net.URI with "literal"), so
%   the canonical form, literal commas included, reaches the server as is.
%
%   A failure with no HTTP response throws an MException; the client turns
%   it into an ensembleweather:connection error.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

uri = matlab.net.URI(char(request.url), "literal");
fields = matlab.net.http.HeaderField.empty;
for i = 1:size(request.headers, 1)
    fields(end + 1) = matlab.net.http.HeaderField( ...
        char(request.headers(i, 1)), char(request.headers(i, 2))); %#ok<AGROW>
end
message = matlab.net.http.RequestMessage(matlab.net.http.RequestMethod.GET, fields);
options = matlab.net.http.HTTPOptions( ...
    "MaxRedirects", 0, ...
    "ConvertResponse", false, ...
    "DecodeResponse", true, ...
    "ConnectTimeout", timeout);
for name = ["ResponseTimeout", "DataTimeout"]
    if isprop(options, name)
        options.(name) = timeout;
    end
end
reply = message.send(uri, options);
response.status = double(reply.StatusCode);
names = strings(0, 1);
values = strings(0, 1);
for f = reshape(reply.Header, 1, [])
    names(end + 1, 1) = string(f.Name); %#ok<AGROW>
    values(end + 1, 1) = string(f.Value); %#ok<AGROW>
end
response.headers = [names values];
body = uint8([]);
if ~isempty(reply.Body) && ~isempty(reply.Body.Data)
    body = reply.Body.Data;
    if ~isa(body, "uint8")
        body = unicode2native(char(string(body)), "UTF-8");
    end
end
response.body = reshape(body, 1, []);
end
