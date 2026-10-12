# Visual Regression Report

- Status: **missing_inputs**
- Generated: `2026-10-04T15:37:15+00:00`
- Canvas: `160 × 120`
- Baselines: `D:\workspace\My\harmony\harmony-PelicanBike\docs\visual-regression\selftest\missing-baselines`
- Actual screenshots: `D:\workspace\My\harmony\harmony-PelicanBike\docs\visual-regression\selftest\missing-actuals`

## Summary

| Scenes | Compared | Passed | Failed | Missing | Errors |
|---:|---:|---:|---:|---:|---:|
| 1 | 0 | 0 | 0 | 1 | 0 |

## Missing inputs

Missing PNGs are reported but do not fail the command unless `--strict-missing` is used.

| Scene | Missing | Baseline patterns | Actual patterns |
|---|---|---|---|
| missing-scene | baseline, actual | `missing.png` | `missing.png` |

## Warnings

- Baseline directory does not exist: D:\workspace\My\harmony\harmony-PelicanBike\docs\visual-regression\selftest\missing-baselines
- Actual screenshot directory does not exist: D:\workspace\My\harmony\harmony-PelicanBike\docs\visual-regression\selftest\missing-actuals

## Metric notes

- MAE/RMSE use an 8-bit RGB scale (0 is identical).
- PSNR is higher-is-better; JSON uses `null` for infinity when images are identical.
- SSIM is a simplified global luminance/contrast/structure score after bounded downsampling.
- Edge score compares Pillow edge maps; histogram distance is normalized to 0–1.
- Score is a heuristic 0–100 blend for triage, not a replacement for the raw metrics.
