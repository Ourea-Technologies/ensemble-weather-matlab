function text = formatNumber(value)
%FORMATNUMBER The shortest decimal that round-trips, never an exponent (internal).
%   TEXT = ensembleweather.internal.formatNumber(VALUE) prints a finite real
%   number as BEHAVIOR.md 3.1 rule 6 asks: 1661 -> "1661", 45.3311 ->
%   "45.3311", 2500.5 -> "2500.5", 1e-7 -> "0.0000001". Coordinates are
%   printed exactly as given; nothing is rounded.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

if ~(isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value))
    ensembleweather.internal.usage("expected a finite real number");
end
value = double(value);
if value == 0
    text = "0";
    return
end
if value == fix(value) && abs(value) < 1e21
    text = string(sprintf("%.0f", value));
    return
end
for digits = 1:17
    candidate = sprintf("%.*g", digits, value);
    if str2double(candidate) == value
        break
    end
end
text = string(candidate);
if contains(text, "e")
    text = plain(text);
end
end

function text = plain(text)
% Rewrite d.ddde[+-]NN without an exponent.
parts = split(text, "e");
mantissa = parts(1);
exponent = str2double(parts(2));
negative = startsWith(mantissa, "-");
mantissa = erase(mantissa, "-");
digits = erase(mantissa, ".");
point = strlength(extractBefore(mantissa + ".", ".")) + exponent;
if point <= 0
    text = "0." + repmat('0', 1, -point) + digits;
elseif point >= strlength(digits)
    text = digits + repmat('0', 1, point - strlength(digits));
else
    text = extractBefore(digits, point + 1) + "." + extractAfter(digits, point);
end
if negative
    text = "-" + text;
end
end
