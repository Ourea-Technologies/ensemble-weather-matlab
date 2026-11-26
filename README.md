# ensemble-weather-matlab

Official MATLAB toolbox for the [Ourea](https://oureawx.com) probabilistic weather API.

[![CI](https://github.com/Ourea-Technologies/ensemble-weather-matlab/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Ourea-Technologies/ensemble-weather-matlab/actions/workflows/ci.yml)
[![Security](https://github.com/Ourea-Technologies/ensemble-weather-matlab/actions/workflows/security.yml/badge.svg?branch=main)](https://github.com/Ourea-Technologies/ensemble-weather-matlab/actions/workflows/security.yml)
[![GitHub release](https://img.shields.io/github/v/release/Ourea-Technologies/ensemble-weather-matlab)](https://github.com/Ourea-Technologies/ensemble-weather-matlab/releases)
[![MATLAB R2023b+](https://img.shields.io/badge/MATLAB-R2023b%2B-orange)](https://github.com/Ourea-Technologies/ensemble-weather-matlab/actions/workflows/ci.yml)
[![Licence: BSD-2-Clause](https://img.shields.io/badge/licence-BSD--2--Clause-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-docs.oureawx.com%2Fmatlab-informational)](https://docs.oureawx.com/matlab)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Ourea-Technologies/ensemble-weather-matlab/badge)](https://scorecard.dev/viewer/?uri=github.com/Ourea-Technologies/ensemble-weather-matlab)

## Install

In MATLAB, open **Add-Ons > Get Add-Ons**, search for **Ourea Ensemble Weather**
and click **Add**. Or download the `.mltbx` from the
[latest release](https://github.com/Ourea-Technologies/ensemble-weather-matlab/releases/latest) and run:

```matlab
matlab.addons.install("ensemble-weather-matlab-0.1.0.mltbx")
```

## Quickstart

No signup and no API key: anonymous calls use the Free tier.

```matlab
client = ensembleweather.Client();  % no key: anonymous calls use the Free tier
forecast = client.forecast("or/mt-hood-meadows", Units="imperial", ...
    Prob=ensembleweather.Chance.atLeast("snowfall", 6, Unit="in"));  % the next 24 h

disp(forecast.location.name)
hours = forecast.series.timeseries;
for hour = reshape(hours(1:min(24, end)), 1, [])
    t = hour.ensemble.temperature;
    fprintf("%s UTC  %g to %g °F (p10-p90)\n", ...
        string(hour.valid_time, "eee HH:mm"), t.p10, t.p90);
end

snow = forecast.probabilities(1);
if isempty(snow.value)
    chance = "not available";
else
    chance = sprintf("%.0f%%", 100 * snow.value);
end
fprintf("Chance of at least 6 in of snow in the next 24 h: %s (%d members)\n", ...
    chance, snow.members);
```

This is [`examples/quickstart.m`](examples/quickstart.m); CI runs it.

## Authentication

Pass a key to the constructor, or set `OUREA_API_KEY`:

```matlab
client = ensembleweather.Client(ApiKey="ow_...");   % or: setenv("OUREA_API_KEY", "ow_...")
```

- **Anonymous** (no key): forecasts, current conditions and alerts for named
  locations at the Free tier (10-day horizon, latest run, the members'
  plume view), plus search and the catalog.
- **Free key**: the same, with your own rate-limit budget.
- **Plus key**: adds the run-by-run snow trend (`snowTrend`).
- **Pro key**: the 15-day horizon, forecasts and current conditions at any
  coordinates (`getPointForecast`, `getPointCurrent`), every member variable,
  per-model breakdowns and historical runs.

See [pricing](https://oureawx.com/pricing). The key is sent only as
`X-API-Key`, only to the API's own host, and never on the open routes
(search, catalog detail, attribution, composition), so those share the edge
cache with everyone; pass `SendKeyOnOpenRoutes=true` to attribute every
request to your key. The key never appears in the client's display or in an
error.

## Probabilities, not single numbers

Every forecast value is a distribution (a quantiles struct: `p10`, `p25`,
`p50`, `p75`, `p90`, `min`, `max`, `mean`) computed by the server from the
full ensemble. Ask for a **chance** of crossing a threshold:

```matlab
client = ensembleweather.Client();
terms = [
    ensembleweather.Chance.atLeast("snowfall", 12, Unit="in", Window=72)   % P(0-72 h snowfall >= 12 in)
    ensembleweather.Chance.atMost("temperature", 32, Unit="degF", Window=[6 18], Aggregation="all")
    ];
forecast = client.forecast("or/mt-hood-meadows", Prob=terms);
for p = forecast.probabilities'   % in your order, each with its reference class
    disp([p.variable p.op p.threshold p.window_start_hours p.window_end_hours p.value p.members])
end
```

For a **storm total**, ask for the window total's distribution:

```matlab
forecast = client.forecast("or/mt-hood-meadows", Totals=ensembleweather.Total("snowfall", 72));
storm = forecast.window_totals(1).quantiles;   % [] (see null_reason) when not covered
```

Read **quantiles** directly; `p50` is the median, not "the forecast". An hourly
series is one call from a timetable:

```matlab
temp = forecast.series.timeseries(1).ensemble.temperature;
ensembleweather.interval(temp)            % [p10 p90]; interval(temp, 25, 75) is [p25 p75]
tt = ensembleweather.toTimetable(forecast);
plot(tt.Time, [tt.temperature_p10 tt.temperature_p50 tt.temperature_p90])
```

The toolbox never sums, averages or interpolates quantiles, and never
derives a probability from them: the sum of hourly medians is not the
median total. A threshold you give in another unit is converted exactly
into the request's units before sending; response values are never
converted. More in [Probabilities](https://docs.oureawx.com/concepts/probabilities).

## Results

Every method returns the response as a struct, and its metadata as a
second output:

```matlab
[forecast, meta] = client.forecast("or/mt-hood-meadows");
meta.rate_limit, meta.request_id, meta.revalidated
```

- Fields have the API reference's names (snake_case), except the renamed ones
  below. A field the server did not send, or sent as `null`, is `[]`.
- A list of objects is an N-by-1 struct array (a cell array where items can be
  `null`); a list of numbers is a column vector with `NaN` for `null`; a list
  of number lists is a matrix (row *i* is item *i*).
- Text is a string; an enumerated value keeps the API's string, so a value
  added to the API later is kept as sent.
- Timestamps are `datetime` in UTC (`t.TimeZone = forecast.location.timezone`
  shows local time).
- The snowpack's `definitions.surface` and `definitions.layer_form` are
  `dictionary` objects (code to text).
- The GeoJSON routes (`alertOutlines`, `avalancheZones`) are passed through
  untouched: every key is the API's and coordinates are the raw numbers.
  `jsonencode` turns one back into GeoJSON for `readgeotable` or a web map.

## Names that differ from the API's JSON

A JSON field that repeats a word of the object holding it would read twice
(`forecast.forecast`, `current.current`, `probability.probability`), so the
toolbox names it differently. There is one table for every Ourea SDK
(ensemble-weather-spec BEHAVIOR.md 3.0); the decoder applies it, and the
spec-drift test checks it against the pinned spec. Every other field keeps
its JSON name. A JSON field named like a MATLAB keyword gets a trailing
underscore (a mountain pass's snow window `end` is `end_`).

| Object | JSON field | Toolbox field |
|---|---|---|
| forecast | `forecast` | `series` |
| forecast | `elevation_forecasts` | `elevations` |
| current conditions response | `current` | `now` |
| current conditions | `condition`, `condition_text`, `condition_icon` | `code`, `text`, `icon` |
| current conditions' station | `station_id` | `id` |
| probability result | `probability` | `value` |
| probability thresholds | `daily_precipitation_probability`, `daily_precipitation_occurrence_probability`, `daily_snow_probability` | `daily_precipitation`, `daily_precipitation_occurrence`, `daily_snow` |
| window total | `window_start_hours`, `window_end_hours` | `start_hours`, `end_hours` |
| an hour's model members | `members` | `items` |
| member forecast | `member_id` | `id` |
| member plume | `members` | `pool` |
| alerts | `alerts`, `alert_count` | `items`, `count` |
| locations page | `locations` | `items` |
| nearby locations | `location`, `locations` | `origin`, `items` |
| nearby a point | `locations` | `items` |
| runs | `runs` | `items` |
| elevation forecast, elevation summary, snow trend elevation | `elevation` | `height` |
| catalog elevation | `elevation_m` | `height_m` |
| catalog station (and its detail) | `source_station_id`, `station_status`, `station_url` | `source_id`, `status`, `url` |
| catalog nearby station | `station_status` | `status` |
| catalog template | `template_variant` | `variant` |
| catalog content entry | `resolved_locale` | `locale` |
| sensor observation | `observation_time` | `observed_at` |
| pass hour | `snow_level_above_pass` | `snow_level_margin` |
| pass road segment | `status`, `status_text` | `state`, `text` |
| avalanche forecast | `forecast_url` | `url` |
| season total | `total` | `amount` |
| snow trend day | `snow` | `amount` |
| error body | `error` | `OureaError.Code` |

## Every route

| Method | Route | Access |
|---|---|---|
| `forecast`, `getPointForecast` | a named location's forecast; one at coordinates | anonymous; Pro |
| `current`, `getPointCurrent` | current conditions (a mountain pass also gets `pass`) | anonymous; Pro |
| `alerts`, `getPointAlerts` | active alerts | anonymous; Pro |
| `nearby`, `getPointNearby` | nearby locations | anonymous |
| `search` | search by name, optionally `Sort` by a metric and `Near` a point | anonymous |
| `explore`, `iterExplore` | places ranked by a metric (`snow_5d`, `base_depth`, `season_precip`, ...) | anonymous |
| `season` | observed season-to-date precipitation and snowfall | anonymous |
| `snowTrend` | each recent run's daily snowfall, run by run | Plus or Pro |
| `snowpack`, `snowpackPlume` | the modelled snowpack and its snow-depth plume (beta) | anonymous |
| `alertOutlines`, `avalancheZones` | GeoJSON for maps: alert outlines, avalanche zones and ratings | anonymous |
| `listLocations`, `iterLocations` | every location, paged | anonymous |
| `listCatalogLocations`, `iterCatalogLocations`, `catalogLocation` | the location catalog | anonymous |
| `listCatalogStations`, `iterCatalogStations`, `catalogStation` | the station catalog | anonymous |
| `runs`, `iterRuns`, `composition`, `attribution` | served runs, the blend's models and members, data credits | anonymous |

`Members="plume"` on a forecast returns the plume view: columns in
`forecast.series.plume`, ready to draw. Every `iter*` method returns an
`ensembleweather.Pager`: `hasNext()`/`next()` fetch a page only when needed,
and `collect()` gathers every item.

## More examples

| Example | Shows |
|---|---|
| [`quickstart.m`](examples/quickstart.m) | the program above, anonymous |
| [`pointForecast.m`](examples/pointForecast.m) | a forecast at coordinates and an elevation (Pro key from `OUREA_API_KEY`) |
| [`chanceOfSnow.m`](examples/chanceOfSnow.m) | several `Prob` terms in one call, with windows and member counts |
| [`stormTotal.m`](examples/stormTotal.m) | `Totals` window distributions for precipitation and snowfall |
| [`searchAndCatalog.m`](examples/searchAndCatalog.m) | search, then page through the catalog with the cursor |
| [`currentAndAlerts.m`](examples/currentAndAlerts.m) | current conditions and active alerts for a location |
| [`errorHandling.m`](examples/errorHandling.m) | catching an out-of-coverage error by its identifier, the keyless alternative to `PRO_REQUIRED`; reading rate-limit state |
| [`units.m`](examples/units.m) | the same forecast in metric and imperial |
| [`snowReport.m`](examples/snowReport.m) | a season to date, a forecast as a timetable, and `explore` rankings |

## Errors, retries and rate limits

Every error is an `ensembleweather.OureaError` (an `MException`). Its
identifier names the category, so a `catch` block can switch on it:

```matlab
try
    client.getPointForecast(45.0, 10.0);
catch err
    if err.identifier == "ensembleweather:outsideCoverage"
        disp(err.Code)   % "OUTSIDE_COVERAGE"
    else
        rethrow(err)
    end
end
```

| Identifier | When |
|---|---|
| `ensembleweather:authentication` | 401: the key is missing where required, unknown or revoked |
| `ensembleweather:permission` | 403: `PRO_REQUIRED`, `PLUS_REQUIRED` (`NearestLocation` names a keyless alternative) |
| `ensembleweather:notFound` | 404, 410 |
| `ensembleweather:invalidRequest` | 400 (`Param` names the parameter) |
| `ensembleweather:outsideCoverage` | `OUTSIDE_COVERAGE` |
| `ensembleweather:rateLimited` | 429 (`RetryAfter`) |
| `ensembleweather:unavailable` | 5xx |
| `ensembleweather:api` | any other HTTP error status |
| `ensembleweather:connection` | no response: DNS, TLS, reset, timeout |
| `ensembleweather:usage` | refused before sending: an invalid term, unit or argument |
| `ensembleweather:unexpectedResponse` | a 2xx body that is not the documented shape |

An HTTP error also carries `Status`, `Code` (the API's string, verbatim),
`RequestId`, `DocUrl` and `RateLimit`. Connection errors, 429, 502, 503 and
504 are retried up to `MaxRetries` (default 2) with full-jitter backoff,
honouring `Retry-After` (on 429, 503 and 504) up to 60 s. Nothing else is
retried. The rate-limit state the server reported is in `meta.rate_limit`
and `client.RateLimit` (`limit`, `remaining`, `reset`, `policy`); the
toolbox never hard-codes limits. A `Deprecation` or `Sunset` header raises
the warning `ensembleweather:deprecated` once per operation per session.

Responses are cached locally by `ETag` (in memory, 256 entries / 32 MiB)
and revalidated on every call, so an unchanged forecast costs a `304`. Pass
`Cache=false` to disable it, or your own `ensembleweather.Cache` subclass to
share one.

## Documentation

- Guides: https://docs.oureawx.com
- This toolbox's guide: https://docs.oureawx.com/matlab
- Reference: `help ensembleweather`, `doc ensembleweather.Client`, and the
  help of every class and method
- The OpenAPI contract: [ensemble-weather-spec](https://github.com/Ourea-Technologies/ensemble-weather-spec/blob/main/openapi/v1/openapi.yaml)
  (a pinned copy is in [`spec/`](spec/))

This toolbox targets API contract **v1**.

## Supported versions

MATLAB R2023b and later (CI tests R2023b, R2024b and the latest release),
on any platform MATLAB runs on. No other toolbox is needed, and there are
no third-party dependencies: HTTP is MATLAB's `matlab.net.http` and JSON its
`jsondecode`.

## Contributing and community

This toolbox is open source and we want it to be the best weather toolbox
in MATLAB. Bug reports, feature requests, docs fixes and pull requests are
all welcome, including small ones.

- **Report a bug**: [open a bug report](https://github.com/Ourea-Technologies/ensemble-weather-matlab/issues/new?template=bug_report.yml)
- **Request a feature** or an API capability: [open a feature request](https://github.com/Ourea-Technologies/ensemble-weather-matlab/issues/new?template=feature_request.yml)
- **Ask a question or share what you built**: [GitHub Discussions](https://github.com/Ourea-Technologies/ensemble-weather-matlab/discussions)
- **Contribute code or docs**: [CONTRIBUTING.md](CONTRIBUTING.md) and the
  [`good first issue`](https://github.com/Ourea-Technologies/ensemble-weather-matlab/labels/good%20first%20issue) label
- **Security issues**: never in public issues; see [SECURITY.md](SECURITY.md)

Licence: [BSD-2-Clause](LICENSE), Copyright (c) 2026 Ourea Technologies.
