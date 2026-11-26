Response bodies captured from https://api.oureawx.com on 2026-11-26 with a
Pro key (the key is not in them), gzipped. `LiveBodiesTest` decodes them, so
the toolbox's decoder is checked against real keyed responses, not only the
spec's vector bodies:

| File | Request |
|---|---|
| `members.json.gz` | `GET /api/v1/locations/or/mt-hood-meadows?elevations=all&max_hours=12&members=true&models=true` |
| `point.json.gz` | `GET /api/v1/forecast?lat=45.3311&lon=-121.6649&max_hours=24&members=true` |
| `pointcurrent.json.gz` | `GET /api/v1/current?lat=45.3311&lon=-121.6649` |
| `trend.json.gz` | `GET /api/v1/locations/or/mt-hood-meadows/snow-trend` |
