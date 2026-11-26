function digest = sha256(text)
%SHA256 The SHA-256 of TEXT's UTF-8 bytes, as 64 lowercase hex digits (internal).
%   The cache keys an entry by the URL plus this hash of the API key, so
%   the key itself is never stored (BEHAVIOR.md 10). Pure MATLAB (FIPS
%   180-4), so the toolbox needs no Java.

%   Copyright (c) 2026 Ourea Technologies. BSD-2-Clause.

k = uint32([ ...
    0x428a2f98 0x71374491 0xb5c0fbcf 0xe9b5dba5 0x3956c25b 0x59f111f1 0x923f82a4 0xab1c5ed5 ...
    0xd807aa98 0x12835b01 0x243185be 0x550c7dc3 0x72be5d74 0x80deb1fe 0x9bdc06a7 0xc19bf174 ...
    0xe49b69c1 0xefbe4786 0x0fc19dc6 0x240ca1cc 0x2de92c6f 0x4a7484aa 0x5cb0a9dc 0x76f988da ...
    0x983e5152 0xa831c66d 0xb00327c8 0xbf597fc7 0xc6e00bf3 0xd5a79147 0x06ca6351 0x14292967 ...
    0x27b70a85 0x2e1b2138 0x4d2c6dfc 0x53380d13 0x650a7354 0x766a0abb 0x81c2c92e 0x92722c85 ...
    0xa2bfe8a1 0xa81a664b 0xc24b8b70 0xc76c51a3 0xd192e819 0xd6990624 0xf40e3585 0x106aa070 ...
    0x19a4c116 0x1e376c08 0x2748774c 0x34b0bcb5 0x391c0cb3 0x4ed8aa4a 0x5b9cca4f 0x682e6ff3 ...
    0x748f82ee 0x78a5636f 0x84c87814 0x8cc70208 0x90befffa 0xa4506ceb 0xbef9a3f7 0xc67178f2]);
h = uint32([0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a ...
    0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19]);

message = double(unicode2native(char(text), "UTF-8"));
bits = numel(message) * 8;
message = [message 128 zeros(1, mod(55 - numel(message), 64))];
lengthBytes = zeros(1, 8);
for i = 8:-1:1
    lengthBytes(i) = mod(bits, 256);
    bits = floor(bits / 256);
end
message = [message lengthBytes];

for block = 1:64:numel(message)
    chunk = message(block:block + 63);
    w = zeros(1, 64, "uint32");
    for t = 1:16
        b = chunk(4 * t - 3:4 * t);
        w(t) = uint32(b(1) * 2^24 + b(2) * 2^16 + b(3) * 2^8 + b(4));
    end
    for t = 17:64
        s0 = bitxor(bitxor(rotr(w(t - 15), 7), rotr(w(t - 15), 18)), bitshift(w(t - 15), -3));
        s1 = bitxor(bitxor(rotr(w(t - 2), 17), rotr(w(t - 2), 19)), bitshift(w(t - 2), -10));
        w(t) = add(w(t - 16), s0, w(t - 7), s1);
    end
    a = h(1); b = h(2); c = h(3); d = h(4);
    e = h(5); f = h(6); g = h(7); hh = h(8);
    for t = 1:64
        S1 = bitxor(bitxor(rotr(e, 6), rotr(e, 11)), rotr(e, 25));
        ch = bitxor(bitand(e, f), bitand(bitcmp(e), g));
        temp1 = add(hh, S1, ch, k(t), w(t));
        S0 = bitxor(bitxor(rotr(a, 2), rotr(a, 13)), rotr(a, 22));
        maj = bitxor(bitxor(bitand(a, b), bitand(a, c)), bitand(b, c));
        temp2 = add(S0, maj);
        hh = g; g = f; f = e;
        e = add(d, temp1);
        d = c; c = b; b = a;
        a = add(temp1, temp2);
    end
    h = [add(h(1), a) add(h(2), b) add(h(3), c) add(h(4), d) ...
        add(h(5), e) add(h(6), f) add(h(7), g) add(h(8), hh)];
end
digest = string(lower(reshape(dec2hex(h, 8)', 1, [])));
end

function out = rotr(x, n)
out = bitor(bitshift(x, -n), bitshift(x, 32 - n));
end

function out = add(varargin)
% Addition modulo 2^32.
total = 0;
for i = 1:nargin
    total = total + double(varargin{i});
end
out = uint32(mod(total, 2^32));
end
