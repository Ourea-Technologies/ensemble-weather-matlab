# Contributing to ensemble-weather-matlab

Thanks for helping make Ourea better. This is the official MATLAB toolbox
for the [Ourea](https://oureawx.com) probabilistic weather API. Its
behaviour is fixed by the shared [SDK spec](spec/BEHAVIOR.md) and
[repository standard](spec/SDK-STANDARD.md), and its public API follows
MATLAB's own conventions (a `+ensembleweather` namespace, name-value
arguments, `MException` identifiers, structs and timetables).

We aim to give a first response to new issues and pull requests within a
few business days.

## Development setup

You need MATLAB R2023b or later (no other toolbox) and, for the example
tests, `python3` (it runs `tests/stub_server.py`, a local stand-in for the
API). Clone the repository and open MATLAB in its root folder.

## Checks

CI runs exactly these; run them before you push:

```matlab
buildtool check     % Code Analyzer with zero issues; no eval/evalin/evalc/assignin in toolbox/
buildtool test      % unit tests, the 58 shared vectors, spec drift, examples (stub server)
buildtool package   % both of the above, then release/ensemble-weather-matlab-<version>.mltbx
```

and, from a shell:

```sh
scripts/sync-spec --check                                  # spec/ matches spec/VERSION
python3 -m pip install --require-hashes -r scripts/requirements.txt
python3 scripts/gen_schema.py --check                      # the decoding table is fresh
```

`buildtool test` runs every vector in `spec/vectors/` against a mock
transport (`tests/+helpers/Replay.m`), and runs every program in
`examples/` and the real `matlab.net.http` transport against
`tests/stub_server.py`. Tests never call the real API. To run one example
by hand against the stub:

```sh
python3 tests/stub_server.py        # prints: export OUREA_BASE_URL=...
```

then, in MATLAB, `setenv("OUREA_BASE_URL", "http://127.0.0.1:PORT")`,
`addpath toolbox` and `run examples/quickstart.m`.

## The spec and the decoding table

`spec/` is a copy of
[ensemble-weather-spec](https://github.com/Ourea-Technologies/ensemble-weather-spec)
at the commit or tag in `spec/VERSION`. Never edit it by hand. The API's
behaviour lives there, so a feature request for the API itself may be moved
to that repository.

```sh
scripts/sync-spec v1.1.0             # pin a new spec version and copy it in
python3 scripts/gen_schema.py        # regenerate the decoding table from it
```

`scripts/gen_schema.py` turns the spec's OpenAPI file and BEHAVIOR.md's
rename table into `toolbox/+ensembleweather/+internal/schema.json` (what the
decoder walks) and `tests/fixtures/spec-examples.json` (what the drift test
decodes). MATLAB has no YAML reader, so this one step is Python. If a vector
looks wrong, open an issue on the spec repository instead of bending the
toolbox to it.

## What makes a good bug report

The toolbox version (`ensembleweather.Client.Version`), your MATLAB release
(`version`) and OS, a minimal snippet, and the request id from the error
(`err.RequestId`) if there is one. Never paste your API key.

## How feature ideas are decided

Open a feature request with the problem first. The maintainers weigh it
against the spec: anything that needs the client to compute statistics is a
request for a new server query instead, and anything the API cannot answer
goes to ensemble-weather-spec (label `needs-spec`).

## Rules of the road

- The server computes, the toolbox carries: no summing, averaging or
  interpolating of quantiles, and no probabilities derived client-side.
- Every bug fix comes with a test that fails without it.
- Every public class, method and function has help text (the H1 line first).
- Commit messages: an imperative summary line (`Add`, `Fix`, ...) of at most
  72 characters, a blank line, then what changed and why. One logical change
  per commit; `main` has a linear history.

## Dependencies

None at run time, and it stays that way unless the maintainers approve one:
HTTP is `matlab.net.http`, JSON is `jsondecode`, and the cache key hash is a
pure-MATLAB SHA-256. The toolbox needs no other MathWorks toolbox. The only
dev dependency is PyYAML for `scripts/gen_schema.py`, pinned by hash in
`scripts/requirements.txt` and never shipped.

## Releasing (maintainers)

1. Update `CHANGELOG.md` (set the date of the version's section) and
   `Version` in `toolbox/+ensembleweather/Client.m`.
2. Merge to `main`, then tag `vX.Y.Z` on it and push the tag.
3. `release.yml` runs CI again, builds the `.mltbx` with `buildtool package`,
   checks that the tag matches `Client.Version`, signs build provenance, and,
   after approval in the `release` environment, creates the GitHub release
   with the `.mltbx` attached.

### MATLAB File Exchange (once)

File Exchange has no upload API; it follows GitHub releases:

1. Sign in at https://www.mathworks.com/matlabcentral/fileexchange with the
   MathWorks account that will own the entry (an Ourea account, not a
   personal one).
2. Choose **Publish your code** > **Link to a GitHub repository**, and
   authorize MathWorks' GitHub app for the Ourea-Technologies organization
   (an organization owner may need to approve it).
3. Pick `Ourea-Technologies/ensemble-weather-matlab`, and choose to publish
   from **GitHub releases** (not the default branch), so File Exchange
   serves the `.mltbx` attached to each release and the Add-On Explorer can
   install it.
4. Title **Ourea Ensemble Weather**; summary "Official MATLAB toolbox for the
   Ourea probabilistic weather API."; tags `ourea`, `weather`, `forecast`,
   `ensemble`, `probabilistic`; licence BSD-2-Clause (read from LICENSE).
5. After that, every GitHub release (each `vX.Y.Z` tag) updates the File
   Exchange entry by itself.
