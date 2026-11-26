# Changelog

All notable changes to this toolbox are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the toolbox
uses [Semantic Versioning](https://semver.org/). Outside contributors are
credited by GitHub handle.

## [0.1.0] - unreleased

The first release: the whole v1 contract of ensemble-weather-spec
`7954268` (the server's public spec at `256cd770`, BEHAVIOR.md 3.0 and 3.1).

### Added

- `ensembleweather.Client`, with one method per operation:
  - forecasts: `forecast`, `getPointForecast` (Pro), with `Prob`
    (`ensembleweather.Chance`) and `Totals` (`ensembleweather.Total`)
    answered in the caller's order, and `Members` true, false or `"plume"`;
  - `current`, `getPointCurrent`, `alerts`, `getPointAlerts`, `nearby`,
    `getPointNearby`;
  - `search` (with `Sort`, `Order`, `Near`, `RadiusKm`, `Units`);
  - `listLocations`, `listCatalogLocations`, `catalogLocation`,
    `listCatalogStations`, `catalogStation`, `runs`, `attribution`;
  - `explore`, `composition`, `season`, `snowTrend` (Plus or Pro),
    `snowpack` and `snowpackPlume` (beta);
  - `alertOutlines` and `avalancheZones` (GeoJSON, passed through untouched);
  - lazy iterators `iterLocations`, `iterCatalogLocations`,
    `iterCatalogStations`, `iterRuns` and `iterExplore`
    (`ensembleweather.Pager`).
- Results are structs with the spec's fields, under the SDK names of
  BEHAVIOR.md 3.0 where a JSON field stutters (`series`, `now`, `value`,
  `items`, ...); timestamps are UTC `datetime`s; the metadata (rate limit,
  request id, revalidation) is the second output.
- `ensembleweather.toTimetable` (an hourly series as a timetable of its
  quantiles) and `ensembleweather.interval` (a served quantile pair).
- Canonical URLs (sorted parameters, defaults omitted, RFC 3986 encoding,
  literal commas in comma lists, `near` and `bbox`), keyless open routes,
  same-host redirects that keep the key and cross-host ones that drop it,
  retries with `Retry-After` and full-jitter backoff, an in-memory ETag cache
  (256 entries / 32 MiB) or your own `ensembleweather.Cache`, and a
  once-per-operation `ensembleweather:deprecated` warning.
- One error type, `ensembleweather.OureaError`, with identifiers
  `ensembleweather:<category>` and `Status`, `Code`, `RequestId`, `DocUrl`,
  `Param`, `RetryAfter`, `RateLimit` and `NearestLocation`.
- Tests: all 58 shared vectors, a spec-drift test against the pinned spec,
  unit tests, and every example plus the real HTTP transport against a local
  stub server. `buildfile.m` with `check`, `test` and `package` (the `.mltbx`).
