% SEARCHANDCATALOG Search for a location, then page through the catalog with the cursor.

client = ensembleweather.Client();
hits = client.search("hood meadows");
for hit = reshape(hits.items, 1, [])
    fprintf("%s: %s (%s), %s County\n", hit.key, hit.name, hit.type, hit.county);
end
if ~isempty(hits.items)  % a hit can be passed straight to forecast
    forecast = client.forecast(hits.items(1));
    fprintf("%s: %d hours\n", forecast.location.name, numel(forecast.series.timeseries));
end

% The lazy iterator follows next_cursor until the last page.
pages = client.iterCatalogLocations(Limit=20);
while pages.hasNext()
    entry = pages.next();
    fprintf("catalog: %s/%s %s\n", entry.state, entry.slug, entry.name);
end

% Or one page at a time:
page = client.listCatalogLocations(Limit=20);
fprintf("first page: %d entries, next cursor %s\n", numel(page.items), ...
    string(page.next_cursor));
