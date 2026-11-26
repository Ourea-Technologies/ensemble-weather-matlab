% CURRENTANDALERTS Current conditions and active alerts for a named location.

client = ensembleweather.Client();
current = client.current("or/mt-hood-meadows");
alerts = client.alerts("or/mt-hood-meadows");

if isempty(current.now)
    disp("No current conditions are served right now.")
else
    c = current.now;
    fprintf("%s at %s UTC: %s, %g °C\n", current.location.name, ...
        string(c.time, "HH:mm"), c.text, c.temperature);
    fprintf("wind %g m/s from %g°, source: %s\n", c.wind_speed, c.wind_direction, c.source);
end
fprintf("%d active alert(s)\n", alerts.count);
for alert = reshape(alerts.items, 1, [])
    fprintf("- %s (%s, %s): %s\n", alert.event, alert.severity, alert.certainty, ...
        alert.headline);
end
