# Pelican Bike asset exporter

This directory contains the repeatable exporter for the original procedural H5 scene. It creates a temporary, injected esbuild bundle, opens it in Chromium through Playwright, serializes the runtime Three.js objects, writes native-friendly assets, and validates the result.

The source repository is never modified. `node_modules` is not created here; the exporter resolves dependencies from the source project's `node_modules` or from `NODE_PATH`/the surrounding Node environment.

## Commands

```powershell
$env:PELICAN_SOURCE = 'D:\workspace\My\h5\claude-opus-5-5-demo\pelican-bike'
node .\export.mjs
node .\validate.mjs
```

Or:

```powershell
npm run all
```

Optional environment variables:

- `PELICAN_SOURCE`: source H5 repository.
- `PELICAN_ASSET_OUTPUT`: generated output directory.
- `PELICAN_CHROMIUM`: Chrome/Edge/Chromium executable.

The committed asset format and native loading details are documented in `docs/asset-export/README.md`.
