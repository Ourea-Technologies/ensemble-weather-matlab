# Security policy

## Reporting a vulnerability

Please report security issues **privately**, through GitHub's
[private vulnerability reporting](https://github.com/Ourea-Technologies/ensemble-weather-matlab/security/advisories/new)
for this repository. Do not open a public issue, pull request or discussion
for a suspected vulnerability.

Include what you found, how to reproduce it, and the toolbox version
(`ensembleweather.Client.Version`). We acknowledge reports within three
working days and keep you informed until a fix is released. We credit
reporters in the advisory unless you prefer otherwise.

## Supported versions

Security fixes go into the latest release. Before 1.0, that is the latest
0.x minor version.

## What the toolbox guarantees

- The API key is sent only as `X-API-Key`, only to the configured base URL's
  origin (a redirect to another host, port or scheme drops it), and never
  appears in the client's display, its properties, or an error's message.
- TLS certificate verification is always on (MATLAB's default for
  `matlab.net.http`); the toolbox has no option to turn it off.
- Response bodies over 64 MiB are an error.
- JSON is parsed with MATLAB's `jsondecode` into fixed, declared shapes; no
  code is evaluated and no type is chosen from the response. The shipped
  code contains no `eval`, `evalin`, `evalc` or `assignin` (a CI gate).

Vulnerabilities in the API service itself (`api.oureawx.com`) can be
reported the same way; we will route them.
