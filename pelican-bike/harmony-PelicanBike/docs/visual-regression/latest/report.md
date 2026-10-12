# Visual Regression Report

- Status: **missing_inputs**
- Generated: `2026-10-04T16:17:26+00:00`
- Canvas: `1320 × 2856`
- Baselines: `D:\workspace\My\harmony\harmony-PelicanBike\docs\web-baseline`
- Actual screenshots: `D:\workspace\My\harmony\harmony-PelicanBike\emulator\screenshots`

## Summary

| Scenes | Compared | Passed | Failed | Missing | Errors |
|---:|---:|---:|---:|---:|---:|
| 12 | 0 | 0 | 0 | 12 | 0 |

## Missing inputs

Missing PNGs are reported but do not fail the command unless `--strict-missing` is used.

| Scene | Missing | Baseline patterns | Actual patterns |
|---|---|---|---|
| day-orbit | actual | `01-day-12-orbit.png, day-orbit.png, *day*orbit*.png` | `day-orbit.png, pura90-day-orbit.png, 01-day-12-orbit.png, *day*orbit*.png` |
| sunset-orbit | actual | `02-sunset-17.35-orbit.png, sunset-orbit.png, *sunset*orbit*.png` | `sunset-orbit.png, pura90-sunset-orbit.png, 02-sunset-17.35-orbit.png, *sunset*orbit*.png` |
| night-orbit | actual | `03-night-23-orbit.png, night-orbit.png, *night*orbit*.png` | `night-orbit.png, pura90-night-orbit.png, 03-night-23-orbit.png, *night*orbit*.png` |
| ride-chase | actual | `04-chase.png, ride-chase.png, chase.png, *chase*.png` | `ride-chase.png, pura90-ride-chase.png, 04-chase.png, *chase*.png` |
| ride-side | actual | `05-side.png, ride-side.png, side.png, *side*.png` | `ride-side.png, pura90-ride-side.png, 05-side.png, *side*.png` |
| ride-cine | actual | `06-cine.png, ride-cine.png, cine.png, *cine*.png` | `ride-cine.png, pura90-ride-cine.png, 06-cine.png, *cine*.png` |
| ride-pov | actual | `07-pov.png, ride-pov.png, pov.png, *pov*.png` | `ride-pov.png, pura90-ride-pov.png, 07-pov.png, *pov*.png` |
| jump | actual | `08-jump.png, jump.png, 08-*jump*.png` | `jump.png, pura90-jump.png, 08-jump.png, 08-*jump*.png` |
| trick | actual | `09-trick.png, trick.png, *trick*.png` | `trick.png, pura90-trick.png, 09-trick.png, *trick*.png` |
| fish-normal-gulp | actual | `10-fish-normal-gulp.png, fish-normal-gulp.png, *fish*normal*gulp*.png` | `fish-normal-gulp.png, pura90-fish-normal-gulp.png, 10-fish-normal-gulp.png, *fish*normal*gulp*.png` |
| fish-golden-gulp | actual | `11-fish-golden-gulp.png, fish-golden-gulp.png, *fish*golden*gulp*.png` | `fish-golden-gulp.png, pura90-fish-golden-gulp.png, 11-fish-golden-gulp.png, *fish*golden*gulp*.png` |
| offshore-jumping-fish | actual | `12-offshore-jumping-fish.png, offshore-jumping-fish.png, *offshore*jumping*fish*.png` | `offshore-jumping-fish.png, pura90-offshore-jumping-fish.png, 12-offshore-jumping-fish.png, *offshore*jumping*fish*.png` |

## Warnings

- Actual screenshot directory does not exist: D:\workspace\My\harmony\harmony-PelicanBike\emulator\screenshots

## Metric notes

- MAE/RMSE use an 8-bit RGB scale (0 is identical).
- PSNR is higher-is-better; JSON uses `null` for infinity when images are identical.
- SSIM is a simplified global luminance/contrast/structure score after bounded downsampling.
- Edge score compares Pillow edge maps; histogram distance is normalized to 0–1.
- Score is a heuristic 0–100 blend for triage, not a replacement for the raw metrics.
