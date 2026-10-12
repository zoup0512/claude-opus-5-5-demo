#!/usr/bin/env python3
"""Repeatable PNG visual regression comparison using only Pillow + stdlib."""

from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import math
import re
import sys
import tempfile
from pathlib import Path
from typing import Any, Iterable

try:
    import PIL
    from PIL import Image, ImageChops, ImageColor, ImageDraw, ImageFilter, ImageOps, ImageStat
except ImportError as exc:  # Keep dependency failures actionable.
    PIL = None  # type: ignore[assignment]
    _PIL_IMPORT_ERROR: Exception | None = exc
else:
    _PIL_IMPORT_ERROR = None

MIN_PILLOW = (10, 0, 0)
DEFAULT_CONFIG_NAME = "config.pura90.json"
PNG_SUFFIX = ".png"


def require_pillow() -> None:
    if _PIL_IMPORT_ERROR is not None:
        print(
            "Pillow is required. Install it with:\n"
            "  python -m pip install -r requirements.txt\n"
            f"Import error: {_PIL_IMPORT_ERROR}",
            file=sys.stderr,
        )
        raise SystemExit(2)


def version_tuple(value: str) -> tuple[int, int, int]:
    values = [int(part) for part in re.findall(r"\d+", value)[:3]]
    return tuple((values + [0, 0, 0])[:3])  # type: ignore[return-value]


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def load_json(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise ValueError(f"Config file does not exist: {path}") from None
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in {path}: line {exc.lineno}, column {exc.colno}: {exc.msg}") from exc
    if not isinstance(data, dict):
        raise ValueError(f"Config root must be an object: {path}")
    return data


def resolve_path(config_path: Path, value: str | Path) -> Path:
    path = Path(value).expanduser()
    if not path.is_absolute():
        path = config_path.parent / path
    return path.resolve()


def as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    return value if isinstance(value, list) else [value]


def merge_dict(*values: Any) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for value in values:
        if isinstance(value, dict):
            result.update(value)
    return result


def parse_color(value: Any, default: str = "#000000") -> tuple[int, int, int]:
    require_pillow()
    try:
        rgb = ImageColor.getrgb(str(value if value is not None else default))
    except ValueError as exc:
        raise ValueError(f"Invalid color {value!r}") from exc
    if len(rgb) == 4:
        return tuple(rgb[:3])  # type: ignore[return-value]
    return tuple(rgb)  # type: ignore[return-value]


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def resampling(name: str) -> Any:
    require_pillow()
    enum = Image.Resampling
    return {
        "nearest": enum.NEAREST,
        "box": enum.BOX,
        "bilinear": enum.BILINEAR,
        "bicubic": enum.BICUBIC,
        "lanczos": enum.LANCZOS,
    }.get(name.lower(), enum.LANCZOS)


def alignment_options(global_config: dict[str, Any], scene: dict[str, Any], side: str) -> dict[str, Any]:
    def normalize(value: Any) -> dict[str, Any]:
        if isinstance(value, str):
            return {"mode": value}
        return value if isinstance(value, dict) else {}

    return merge_dict(
        {"mode": "letterbox", "background": "#000000", "anchor": [0.5, 0.5], "filter": "lanczos"},
        normalize(global_config.get("alignment")),
        normalize(scene.get("alignment")),
        normalize(global_config.get(f"{side}_alignment")),
        normalize(scene.get(f"{side}_alignment")),
    )


def normalize_image(path: Path, canvas: tuple[int, int], options: dict[str, Any]) -> tuple[Any, dict[str, Any]]:
    require_pillow()
    target_w, target_h = canvas
    if target_w <= 0 or target_h <= 0:
        raise ValueError(f"Canvas must be positive, got {canvas}")

    background = parse_color(options.get("background", "#000000"))
    anchor_value = options.get("anchor", [0.5, 0.5])
    if not isinstance(anchor_value, list) or len(anchor_value) != 2:
        raise ValueError("alignment.anchor must be [x, y]")
    anchor_x = min(1.0, max(0.0, float(anchor_value[0])))
    anchor_y = min(1.0, max(0.0, float(anchor_value[1])))
    mode = str(options.get("mode", "letterbox")).lower()
    filter_name = str(options.get("filter", "lanczos"))
    filter_value = resampling(filter_name)

    try:
        with Image.open(path) as opened:
            opened.load()
            source = ImageOps.exif_transpose(opened)
            original_size = source.size
            if source.mode in {"RGBA", "LA"} or "transparency" in source.info:
                rgba = source.convert("RGBA")
                flattened = Image.new("RGBA", rgba.size, background + (255,))
                flattened.alpha_composite(rgba)
                source_rgb = flattened.convert("RGB")
            else:
                source_rgb = source.convert("RGB")
    except Exception as exc:
        raise ValueError(f"Unable to read PNG {path}: {exc}") from exc

    source_w, source_h = source_rgb.size
    transform: dict[str, Any] = {
        "mode": mode,
        "filter": filter_name,
        "anchor": [anchor_x, anchor_y],
        "background": "#%02x%02x%02x" % background,
        "original_size": [original_size[0], original_size[1]],
        "target_size": [target_w, target_h],
    }

    if mode == "none":
        if source_rgb.size != canvas:
            raise ValueError(f"alignment mode 'none' requires {canvas}, got {source_rgb.size} for {path}")
        transform.update({"scale": 1.0, "offset": [0, 0]})
        return source_rgb, transform

    if mode in {"resize", "stretch"}:
        transform.update({"scale": [target_w / source_w, target_h / source_h], "offset": [0, 0]})
        return source_rgb.resize(canvas, filter_value), transform

    if mode == "letterbox":
        scale = min(target_w / source_w, target_h / source_h)
        scaled = (max(1, round(source_w * scale)), max(1, round(source_h * scale)))
        resized = source_rgb.resize(scaled, filter_value)
        offset_x = round((target_w - scaled[0]) * anchor_x)
        offset_y = round((target_h - scaled[1]) * anchor_y)
        result = Image.new("RGB", canvas, background)
        result.paste(resized, (offset_x, offset_y))
        transform.update({"scale": scale, "scaled_size": list(scaled), "offset": [offset_x, offset_y]})
        return result, transform

    if mode in {"crop", "cover"}:
        scale = max(target_w / source_w, target_h / source_h)
        scaled = (max(1, round(source_w * scale)), max(1, round(source_h * scale)))
        resized = source_rgb.resize(scaled, filter_value)
        crop_x = round((scaled[0] - target_w) * anchor_x)
        crop_y = round((scaled[1] - target_h) * anchor_y)
        crop_x = min(max(0, crop_x), max(0, scaled[0] - target_w))
        crop_y = min(max(0, crop_y), max(0, scaled[1] - target_h))
        result = resized.crop((crop_x, crop_y, crop_x + target_w, crop_y + target_h))
        transform.update({"scale": scale, "scaled_size": list(scaled), "crop_origin": [crop_x, crop_y]})
        return result, transform

    raise ValueError(f"Unsupported alignment mode {mode!r}; use resize, letterbox, crop, or none")


def coordinate(value: Any, extent: int, unit: str) -> int:
    number = float(value)
    if unit in {"normalized", "relative", "ratio", "norm"}:
        number *= extent
    return round(number)


def draw_region(draw: Any, region: Any, size: tuple[int, int], fill: int) -> None:
    width, height = size
    if isinstance(region, list) and len(region) == 4:
        region = {"rect": region, "unit": "normalized" if all(abs(float(v)) <= 1 for v in region) else "px"}
    if not isinstance(region, dict):
        raise ValueError(f"Region must be an object or [x, y, width, height], got {region!r}")
    if region.get("enabled", True) is False:
        return

    unit = str(region.get("unit", "normalized")).lower()
    if "rect" in region:
        rect = region["rect"]
    elif all(key in region for key in ("x", "y", "width", "height")):
        rect = [region["x"], region["y"], region["width"], region["height"]]
    else:
        rect = None

    if rect is not None:
        if not isinstance(rect, list) or len(rect) != 4:
            raise ValueError(f"Region rect must be [x, y, width, height], got {rect!r}")
        x0 = coordinate(rect[0], width, unit)
        y0 = coordinate(rect[1], height, unit)
        rect_w = coordinate(rect[2], width, unit)
        rect_h = coordinate(rect[3], height, unit)
        x1 = x0 + rect_w
        y1 = y0 + rect_h
        x0, x1 = sorted((max(0, min(width, x0)), max(0, min(width, x1))))
        y0, y1 = sorted((max(0, min(height, y0)), max(0, min(height, y1))))
        if x1 > x0 and y1 > y0:
            draw.rectangle((x0, y0, x1 - 1, y1 - 1), fill=fill)
        return

    if "polygon" in region:
        points = region["polygon"]
        if not isinstance(points, list) or len(points) < 3:
            raise ValueError("Region polygon needs at least three [x, y] points")
        converted = [
            (coordinate(point[0], width, unit), coordinate(point[1], height, unit))
            for point in points
            if isinstance(point, list) and len(point) == 2
        ]
        if len(converted) != len(points):
            raise ValueError(f"Invalid polygon points: {points!r}")
        draw.polygon(converted, fill=fill)
        return

    raise ValueError(f"Region requires rect or polygon: {region!r}")


def region_list(value: Any) -> list[Any]:
    if isinstance(value, dict) and "regions" in value:
        return as_list(value["regions"])
    return as_list(value)


def apply_regions(mask: Any, regions: Any, fill: int) -> None:
    require_pillow()
    draw = ImageDraw.Draw(mask)
    for region in region_list(regions):
        draw_region(draw, region, mask.size, fill)


def safe_area_pixels(safe_area: dict[str, Any], size: tuple[int, int]) -> dict[str, int]:
    width, height = size
    unit = str(safe_area.get("unit", "px")).lower()
    return {
        "top": max(0, min(height, coordinate(safe_area.get("top", 0), height, unit))),
        "bottom": max(0, min(height, coordinate(safe_area.get("bottom", 0), height, unit))),
        "left": max(0, min(width, coordinate(safe_area.get("left", 0), width, unit))),
        "right": max(0, min(width, coordinate(safe_area.get("right", 0), width, unit))),
    }


def pixel_count(mask: Any) -> int:
    require_pillow()
    return round(ImageStat.Stat(mask).sum[0] / 255.0)


def build_valid_mask(
    config: dict[str, Any], scene: dict[str, Any], size: tuple[int, int]
) -> tuple[Any, dict[str, Any]]:
    require_pillow()
    width, height = size
    mask_config = config.get("mask", {}) if isinstance(config.get("mask", {}), dict) else {}
    scene_mask = scene.get("mask", {}) if isinstance(scene.get("mask", {}), dict) else {}
    mask = Image.new("L", size, 255)
    draw = ImageDraw.Draw(mask)

    safe_area = merge_dict(mask_config.get("safe_area"), scene_mask.get("safe_area"))
    safe_pixels = {"top": 0, "bottom": 0, "left": 0, "right": 0}
    if safe_area and safe_area.get("enabled", True):
        safe_pixels = safe_area_pixels(safe_area, size)
        if safe_pixels["top"]:
            draw.rectangle((0, 0, width - 1, safe_pixels["top"] - 1), fill=0)
        if safe_pixels["bottom"]:
            draw.rectangle((0, height - safe_pixels["bottom"], width - 1, height - 1), fill=0)
        if safe_pixels["left"]:
            draw.rectangle((0, 0, safe_pixels["left"] - 1, height - 1), fill=0)
        if safe_pixels["right"]:
            draw.rectangle((width - safe_pixels["right"], 0, width - 1, height - 1), fill=0)

    sets = merge_dict(mask_config.get("ignore_region_sets"), scene_mask.get("ignore_region_sets"))
    default_ignore = [str(name) for name in as_list(mask_config.get("default_ignore"))]
    if scene.get("replace_default_ignore", False) or scene_mask.get("replace_default_ignore", False):
        ignore_names: list[str] = []
    else:
        ignore_names = default_ignore
    ignore_names.extend(str(name) for name in as_list(scene.get("ignore")))
    ignore_names.extend(str(name) for name in as_list(scene_mask.get("ignore")))
    ignore_names = list(dict.fromkeys(ignore_names))

    unknown: list[str] = []
    for name in ignore_names:
        if name not in sets:
            unknown.append(name)
            continue
        apply_regions(mask, sets[name], 0)

    inline_regions = as_list(mask_config.get("ignore_regions")) + as_list(scene.get("ignore_regions")) + as_list(
        scene_mask.get("ignore_regions")
    )
    apply_regions(mask, inline_regions, 0)

    valid = pixel_count(mask)
    return mask, {
        "safe_area_excluded_px": safe_pixels,
        "ignore_sets": ignore_names,
        "unknown_ignore_sets": unknown,
        "inline_region_count": len(inline_regions),
        "valid_pixels": valid,
        "total_pixels": width * height,
        "coverage": round(valid / (width * height), 6) if width and height else 0.0,
    }


def build_roi_masks(
    config: dict[str, Any], scene: dict[str, Any], valid_mask: Any
) -> tuple[dict[str, Any], list[str]]:
    require_pillow()
    definitions = merge_dict(config.get("rois"), scene.get("rois"))
    masks: dict[str, Any] = {}
    warnings: list[str] = []
    for name, specification in definitions.items():
        if specification is None or (isinstance(specification, dict) and specification.get("enabled", True) is False):
            continue
        roi = Image.new("L", valid_mask.size, 0)
        try:
            apply_regions(roi, specification, 255)
        except ValueError as exc:
            warnings.append(f"ROI {name!r} is invalid: {exc}")
            continue
        masks[str(name)] = ImageChops.multiply(roi, valid_mask)
    return masks, warnings


def clear_edge_border(image: Any) -> Any:
    require_pillow()
    if image.width > 2 and image.height > 2:
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, image.width - 1, image.height - 1), outline=0, width=1)
    return image


class MetricContext:
    def __init__(self, baseline: Any, actual: Any, changed_threshold: int, ssim_max_dimension: int = 256) -> None:
        require_pillow()
        self.baseline = baseline
        self.actual = actual
        self.diff = ImageChops.difference(baseline, actual)
        channels = self.diff.split()
        self.diff_max = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
        self.changed = self.diff_max.point(lambda value: 255 if value > changed_threshold else 0)
        self.gray_baseline = ImageOps.grayscale(baseline)
        self.gray_actual = ImageOps.grayscale(actual)
        self.edge_baseline = clear_edge_border(self.gray_baseline.filter(ImageFilter.FIND_EDGES))
        self.edge_actual = clear_edge_border(self.gray_actual.filter(ImageFilter.FIND_EDGES))
        scale = min(1.0, ssim_max_dimension / max(baseline.size))
        sample_size = (max(1, round(baseline.width * scale)), max(1, round(baseline.height * scale)))
        self.sample_size = sample_size
        self.sample_baseline = self.gray_baseline.resize(sample_size, Image.Resampling.BOX)
        self.sample_actual = self.gray_actual.resize(sample_size, Image.Resampling.BOX)


def global_ssim(context: MetricContext, mask: Any) -> float:
    require_pillow()
    sample_mask = mask.resize(context.sample_size, Image.Resampling.NEAREST)
    bytes_a = context.sample_baseline.tobytes()
    bytes_b = context.sample_actual.tobytes()
    bytes_m = sample_mask.tobytes()

    count = 0
    sum_a = 0.0
    sum_b = 0.0
    sum_aa = 0.0
    sum_bb = 0.0
    sum_ab = 0.0
    for value_a, value_b, valid in zip(bytes_a, bytes_b, bytes_m):
        if not valid:
            continue
        count += 1
        sum_a += value_a
        sum_b += value_b
        sum_aa += value_a * value_a
        sum_bb += value_b * value_b
        sum_ab += value_a * value_b

    if count == 0:
        return 0.0
    mean_a = sum_a / count
    mean_b = sum_b / count
    variance_a = max(0.0, sum_aa / count - mean_a * mean_a)
    variance_b = max(0.0, sum_bb / count - mean_b * mean_b)
    covariance = sum_ab / count - mean_a * mean_b
    c1 = (0.01 * 255.0) ** 2
    c2 = (0.03 * 255.0) ** 2
    denominator = (mean_a * mean_a + mean_b * mean_b + c1) * (variance_a + variance_b + c2)
    if denominator == 0:
        return 1.0
    value = ((2 * mean_a * mean_b + c1) * (2 * covariance + c2)) / denominator
    return min(1.0, max(-1.0, value))


def histogram_distance(baseline: Any, actual: Any, mask: Any, count: int) -> float:
    if count <= 0:
        return 1.0
    hist_a = baseline.histogram(mask=mask)
    hist_b = actual.histogram(mask=mask)
    distances = []
    for channel in range(3):
        start = channel * 256
        distance = sum(abs(hist_a[index] - hist_b[index]) for index in range(start, start + 256)) / (2.0 * count)
        distances.append(distance)
    return sum(distances) / 3.0


def edge_structure_score(context: MetricContext, mask: Any) -> float:
    require_pillow()
    edge_diff = ImageChops.difference(context.edge_baseline, context.edge_actual)
    edge_union = ImageChops.lighter(context.edge_baseline, context.edge_actual)
    diff_sum = ImageStat.Stat(edge_diff, mask).sum[0]
    union_sum = ImageStat.Stat(edge_union, mask).sum[0]
    if union_sum <= 1e-9:
        return 1.0
    return max(0.0, min(1.0, 1.0 - diff_sum / union_sum))


def round_metric(value: float, digits: int = 6) -> float:
    if math.isinf(value) or math.isnan(value):
        return value
    return round(value, digits)


def compute_metrics(context: MetricContext, mask: Any) -> dict[str, Any]:
    require_pillow()
    count = pixel_count(mask)
    if count <= 0:
        return {"status": "empty", "pixel_count": 0}

    stats = ImageStat.Stat(context.diff, mask)
    channel_mae = [float(value) for value in stats.mean[:3]]
    channel_rms = [float(value) for value in stats.rms[:3]]
    mae = sum(channel_mae) / 3.0
    rmse = math.sqrt(sum(value * value for value in channel_rms) / 3.0)
    psnr = math.inf if rmse == 0 else 20.0 * math.log10(255.0 / rmse)
    changed_ratio = ImageStat.Stat(context.changed, mask).mean[0] / 255.0
    ssim = global_ssim(context, mask)
    edge_score = edge_structure_score(context, mask)
    hist_distance = histogram_distance(context.baseline, context.actual, mask, count)

    pixel_similarity = max(0.0, 1.0 - mae / 64.0)
    ssim_similarity = max(0.0, ssim)
    histogram_similarity = max(0.0, 1.0 - hist_distance)
    visual_score = 100.0 * (
        0.35 * pixel_similarity + 0.30 * ssim_similarity + 0.20 * edge_score + 0.15 * histogram_similarity
    )

    return {
        "status": "ok",
        "pixel_count": count,
        "mae": round_metric(mae),
        "mae_rgb": [round_metric(value) for value in channel_mae],
        "rmse": round_metric(rmse),
        "rmse_rgb": [round_metric(value) for value in channel_rms],
        "psnr_db": round_metric(psnr),
        "ssim_global": round_metric(ssim),
        "edge_structure_score": round_metric(edge_score),
        "histogram_distance": round_metric(hist_distance),
        "changed_pixel_ratio": round_metric(changed_ratio),
        "visual_score": round_metric(visual_score, 3),
    }


THRESHOLD_RULES: dict[str, tuple[str, str]] = {
    "mae_max": ("mae", "max"),
    "rmse_max": ("rmse", "max"),
    "psnr_min": ("psnr_db", "min"),
    "ssim_min": ("ssim_global", "min"),
    "edge_structure_min": ("edge_structure_score", "min"),
    "histogram_distance_max": ("histogram_distance", "max"),
    "changed_pixel_ratio_max": ("changed_pixel_ratio", "max"),
    "visual_score_min": ("visual_score", "min"),
}


def evaluate_thresholds(metrics: dict[str, Any], thresholds: dict[str, Any]) -> tuple[bool, list[dict[str, Any]]]:
    if metrics.get("status") != "ok":
        return False, []
    checks: list[dict[str, Any]] = []
    passed = True
    for threshold_name, (metric_name, direction) in THRESHOLD_RULES.items():
        if threshold_name not in thresholds:
            continue
        limit = float(thresholds[threshold_name])
        value = float(metrics[metric_name])
        check_passed = value <= limit if direction == "max" else value >= limit
        passed = passed and check_passed
        checks.append(
            {
                "threshold": threshold_name,
                "metric": metric_name,
                "operator": "<=" if direction == "max" else ">=",
                "limit": limit,
                "value": value,
                "passed": check_passed,
            }
        )
    return passed, checks


def slugify(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip()).strip("-.")
    return slug or "scene"


def add_header(image: Any, left: str, right: str | None = None) -> Any:
    require_pillow()
    header = 44
    result = Image.new("RGB", (image.width, image.height + header), "#161a22")
    result.paste(image, (0, header))
    draw = ImageDraw.Draw(result)
    draw.text((12, 14), left, fill="#f4f6fb")
    if right:
        bbox = draw.textbbox((0, 0), right)
        draw.text((max(12, image.width - (bbox[2] - bbox[0]) - 12), 14), right, fill="#f4f6fb")
    return result


def create_artifacts(
    output_dir: Path, scene_name: str, baseline: Any, actual: Any, context: MetricContext, mask: Any
) -> dict[str, str]:
    require_pillow()
    scene_dir = output_dir / slugify(scene_name)
    scene_dir.mkdir(parents=True, exist_ok=True)

    gap = 4
    side = Image.new("RGB", (baseline.width * 2 + gap, baseline.height), "#ffffff")
    side.paste(baseline, (0, 0))
    side.paste(actual, (baseline.width + gap, 0))
    side = add_header(side, "BASELINE", "ACTUAL")

    overlay = Image.blend(baseline, actual, 0.5)
    ignored_fill = Image.new("RGB", overlay.size, "#303038")
    overlay = Image.composite(overlay, ignored_fill, mask)
    overlay = add_header(overlay, "ALPHA OVERLAY 50% (ignored regions are gray)")

    heat_gray = context.diff_max
    heat = ImageOps.colorize(
        heat_gray,
        black="#071426",
        mid="#f03b20",
        white="#fff7a8",
        blackpoint=0,
        midpoint=42,
        whitepoint=255,
    )
    heat = Image.composite(heat, Image.new("RGB", heat.size, "#303038"), mask)
    heat = add_header(heat, "ABSOLUTE DIFFERENCE HEATMAP (ignored regions are gray)")

    side_path = scene_dir / "side-by-side.png"
    overlay_path = scene_dir / "alpha-overlay.png"
    heat_path = scene_dir / "heatmap.png"
    side.save(side_path, format="PNG", compress_level=6)
    overlay.save(overlay_path, format="PNG", compress_level=6)
    heat.save(heat_path, format="PNG", compress_level=6)

    return {
        "side_by_side": side_path.relative_to(output_dir).as_posix(),
        "alpha_overlay": overlay_path.relative_to(output_dir).as_posix(),
        "heatmap": heat_path.relative_to(output_dir).as_posix(),
    }


def all_pngs(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(
        (path for path in directory.rglob("*") if path.is_file() and path.suffix.lower() == PNG_SUFFIX),
        key=lambda path: path.as_posix().lower(),
    )


def match_files(directory: Path, patterns: Iterable[str]) -> list[Path]:
    files = all_pngs(directory)
    matched: list[Path] = []
    seen: set[Path] = set()
    for raw_pattern in patterns:
        pattern = str(raw_pattern).replace("\\", "/").lstrip("./").lower()
        for path in files:
            relative = path.relative_to(directory).as_posix().lower()
            name = path.name.lower()
            candidate = relative if "/" in pattern else name
            if fnmatch.fnmatchcase(candidate, pattern) and path not in seen:
                matched.append(path)
                seen.add(path)
    return matched


def select_input(directory: Path, patterns: list[str]) -> tuple[Path | None, list[Path]]:
    candidates = match_files(directory, patterns)
    return (candidates[0] if candidates else None), candidates


def input_description(path: Path, transform: dict[str, Any]) -> dict[str, Any]:
    return {
        "path": str(path),
        "sha256": file_sha256(path),
        "bytes": path.stat().st_size,
        "transform": transform,
    }


def metric_display(value: Any, digits: int = 3) -> str:
    if value is None:
        return "—"
    if isinstance(value, float) and math.isinf(value):
        return "∞"
    if isinstance(value, (float, int)):
        return f"{value:.{digits}f}"
    return str(value)


def json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    if isinstance(value, float):
        if math.isinf(value):
            return None
        if math.isnan(value):
            return None
    return value


def report_status(summary: dict[str, int]) -> str:
    if summary["errors"]:
        return "error"
    if summary["failed"]:
        return "failed"
    if summary["compared"] == 0 and summary["missing"]:
        return "missing_inputs"
    if summary["missing"]:
        return "partial"
    return "passed"


def markdown_report(report: dict[str, Any]) -> str:
    lines: list[str] = [
        "# Visual Regression Report",
        "",
        f"- Status: **{report['status']}**",
        f"- Generated: `{report['generated_at']}`",
        f"- Canvas: `{report['canvas']['width']} × {report['canvas']['height']}`",
        f"- Baselines: `{report['paths']['baseline_dir']}`",
        f"- Actual screenshots: `{report['paths']['actual_dir']}`",
        "",
        "## Summary",
        "",
        "| Scenes | Compared | Passed | Failed | Missing | Errors |",
        "|---:|---:|---:|---:|---:|---:|",
        (
            f"| {report['summary']['total']} | {report['summary']['compared']} | "
            f"{report['summary']['passed']} | {report['summary']['failed']} | "
            f"{report['summary']['missing']} | {report['summary']['errors']} |"
        ),
        "",
    ]

    compared = [scene for scene in report["scenes"] if scene.get("metrics")]
    if compared:
        lines.extend(
            [
                "## Scene metrics",
                "",
                "| Scene | Status | MAE | RMSE | PSNR dB | SSIM | Edge | Hist Δ | Changed | Score |",
                "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|",
            ]
        )
        for scene in compared:
            metric = scene["metrics"]
            lines.append(
                f"| {scene['name']} | {scene['status']} | {metric_display(metric.get('mae'))} | "
                f"{metric_display(metric.get('rmse'))} | {metric_display(metric.get('psnr_db'))} | "
                f"{metric_display(metric.get('ssim_global'))} | "
                f"{metric_display(metric.get('edge_structure_score'))} | "
                f"{metric_display(metric.get('histogram_distance'))} | "
                f"{metric_display(metric.get('changed_pixel_ratio') * 100 if metric.get('changed_pixel_ratio') is not None else None, 2)}% | "
                f"{metric_display(metric.get('visual_score'), 1)} |"
            )
        lines.append("")

    missing = [scene for scene in report["scenes"] if scene["status"] == "missing"]
    if missing:
        lines.extend(
            [
                "## Missing inputs",
                "",
                "Missing PNGs are reported but do not fail the command unless `--strict-missing` is used.",
                "",
                "| Scene | Missing | Baseline patterns | Actual patterns |",
                "|---|---|---|---|",
            ]
        )
        for scene in missing:
            lines.append(
                f"| {scene['name']} | {', '.join(scene['missing'])} | "
                f"`{', '.join(scene['patterns']['baseline'])}` | `{', '.join(scene['patterns']['actual'])}` |"
            )
        lines.append("")

    for scene in compared:
        lines.extend([f"## {scene['name']}", "", f"Status: **{scene['status']}**", ""])
        artifacts = scene.get("artifacts", {})
        if artifacts:
            lines.extend(
                [
                    f"[Side-by-side]({artifacts['side_by_side']}) · "
                    f"[Alpha overlay]({artifacts['alpha_overlay']}) · "
                    f"[Heatmap]({artifacts['heatmap']})",
                    "",
                    f"![{scene['name']} side-by-side]({artifacts['side_by_side']})",
                    "",
                    f"![{scene['name']} heatmap]({artifacts['heatmap']})",
                    "",
                ]
            )
        rois = scene.get("rois", {})
        if rois:
            lines.extend(
                [
                    "### ROI metrics",
                    "",
                    "| ROI | Pixels | MAE | RMSE | SSIM | Edge | Hist Δ | Score | Status |",
                    "|---|---:|---:|---:|---:|---:|---:|---:|---|",
                ]
            )
            for name, roi in rois.items():
                metric = roi.get("metrics", {})
                lines.append(
                    f"| {name} | {metric.get('pixel_count', 0)} | {metric_display(metric.get('mae'))} | "
                    f"{metric_display(metric.get('rmse'))} | {metric_display(metric.get('ssim_global'))} | "
                    f"{metric_display(metric.get('edge_structure_score'))} | "
                    f"{metric_display(metric.get('histogram_distance'))} | "
                    f"{metric_display(metric.get('visual_score'), 1)} | {roi.get('status', '—')} |"
                )
            lines.append("")

        failed_checks = [check for check in scene.get("checks", []) if not check["passed"]]
        if failed_checks:
            lines.extend(["### Failed thresholds", ""])
            for check in failed_checks:
                lines.append(
                    f"- `{check['metric']}` = {metric_display(check['value'])} must be "
                    f"`{check['operator']} {check['limit']}`"
                )
            lines.append("")

    errors = [scene for scene in report["scenes"] if scene["status"] == "error"]
    if errors:
        lines.extend(["## Errors", ""])
        for scene in errors:
            lines.append(f"- **{scene['name']}**: {scene.get('error', 'unknown error')}")
        lines.append("")

    warnings = report.get("warnings", [])
    if warnings:
        lines.extend(["## Warnings", ""])
        lines.extend(f"- {warning}" for warning in warnings)
        lines.append("")

    lines.extend(
        [
            "## Metric notes",
            "",
            "- MAE/RMSE use an 8-bit RGB scale (0 is identical).",
            "- PSNR is higher-is-better; JSON uses `null` for infinity when images are identical.",
            "- SSIM is a simplified global luminance/contrast/structure score after bounded downsampling.",
            "- Edge score compares Pillow edge maps; histogram distance is normalized to 0–1.",
            "- Score is a heuristic 0–100 blend for triage, not a replacement for the raw metrics.",
            "",
        ]
    )
    return "\n".join(lines)


def scene_thresholds(config: dict[str, Any], scene: dict[str, Any]) -> dict[str, Any]:
    return merge_dict(config.get("thresholds"), scene.get("thresholds"))


def roi_thresholds(config: dict[str, Any], scene: dict[str, Any], roi_name: str) -> dict[str, Any]:
    base = scene_thresholds(config, scene)
    global_roi = config.get("roi_thresholds", {})
    scene_roi = scene.get("roi_thresholds", {})
    return merge_dict(
        base,
        global_roi.get("*", {}) if isinstance(global_roi, dict) else {},
        global_roi.get(roi_name, {}) if isinstance(global_roi, dict) else {},
        scene_roi.get("*", {}) if isinstance(scene_roi, dict) else {},
        scene_roi.get(roi_name, {}) if isinstance(scene_roi, dict) else {},
    )


def compare(config_path: Path, args: argparse.Namespace) -> tuple[dict[str, Any], int]:
    require_pillow()
    config = load_json(config_path)
    canvas_config = config.get("canvas", {})
    try:
        canvas = (int(canvas_config.get("width", 1320)), int(canvas_config.get("height", 2856)))
    except (TypeError, ValueError) as exc:
        raise ValueError("canvas.width and canvas.height must be integers") from exc

    paths_config = config.get("paths", {}) if isinstance(config.get("paths", {}), dict) else {}

    def input_path(override: Path | None, config_key: str, default: str) -> Path:
        if override is not None:
            return override.expanduser().resolve()
        return resolve_path(config_path, paths_config.get(config_key, default))

    baseline_dir = input_path(args.baseline_dir, "baseline_dir", "../../docs/web-baseline")
    actual_dir = input_path(args.actual_dir, "actual_dir", "../../emulator/screenshots")
    output_dir = input_path(args.output_dir, "output_dir", "../../docs/visual-regression/latest")
    output_dir.mkdir(parents=True, exist_ok=True)

    configured_scenes = config.get("scenes", {})
    if not isinstance(configured_scenes, dict) or not configured_scenes:
        raise ValueError("Config must define a non-empty scenes object")
    selected = set(args.scene or [])
    if selected:
        unknown = selected.difference(configured_scenes)
        if unknown:
            raise ValueError(f"Unknown scene(s): {', '.join(sorted(unknown))}")

    report: dict[str, Any] = {
        "schema_version": 1,
        "tool": "pelican-bike-visual-compare",
        "tool_version": "1.0.0",
        "generated_at": utc_now(),
        "config": str(config_path),
        "pillow_version": PIL.__version__,
        "canvas": {"width": canvas[0], "height": canvas[1]},
        "paths": {
            "baseline_dir": str(baseline_dir),
            "actual_dir": str(actual_dir),
            "output_dir": str(output_dir),
        },
        "summary": {"total": 0, "compared": 0, "passed": 0, "failed": 0, "missing": 0, "errors": 0},
        "status": "pending",
        "warnings": [],
        "scenes": [],
    }

    if not baseline_dir.is_dir():
        report["warnings"].append(f"Baseline directory does not exist: {baseline_dir}")
    if not actual_dir.is_dir():
        report["warnings"].append(f"Actual screenshot directory does not exist: {actual_dir}")

    comparison_config = config.get("comparison", {}) if isinstance(config.get("comparison", {}), dict) else {}
    changed_threshold = int(comparison_config.get("changed_pixel_threshold", 12))
    ssim_max_dimension = int(comparison_config.get("ssim_max_dimension", 256))
    fail_on_rois = bool(comparison_config.get("fail_on_rois", False))

    for scene_name, raw_scene in configured_scenes.items():
        if selected and scene_name not in selected:
            continue
        if raw_scene is None:
            raw_scene = {}
        if not isinstance(raw_scene, dict):
            raise ValueError(f"Scene {scene_name!r} must be an object")
        if raw_scene.get("enabled", True) is False:
            continue

        report["summary"]["total"] += 1
        baseline_patterns = [str(value) for value in as_list(raw_scene.get("baseline", f"{scene_name}.png"))]
        actual_patterns = [str(value) for value in as_list(raw_scene.get("actual", f"{scene_name}.png"))]
        baseline_path, baseline_candidates = select_input(baseline_dir, baseline_patterns)
        actual_path, actual_candidates = select_input(actual_dir, actual_patterns)
        scene_report: dict[str, Any] = {
            "name": scene_name,
            "status": "pending",
            "patterns": {"baseline": baseline_patterns, "actual": actual_patterns},
            "candidate_count": {"baseline": len(baseline_candidates), "actual": len(actual_candidates)},
        }

        if len(baseline_candidates) > 1:
            report["warnings"].append(
                f"Scene {scene_name!r} baseline matched {len(baseline_candidates)} files; using {baseline_candidates[0]}"
            )
        if len(actual_candidates) > 1:
            report["warnings"].append(
                f"Scene {scene_name!r} actual matched {len(actual_candidates)} files; using {actual_candidates[0]}"
            )

        missing: list[str] = []
        if baseline_path is None:
            missing.append("baseline")
        if actual_path is None:
            missing.append("actual")
        if missing:
            scene_report.update({"status": "missing", "missing": missing})
            report["summary"]["missing"] += 1
            report["scenes"].append(scene_report)
            continue

        try:
            baseline, baseline_transform = normalize_image(
                baseline_path, canvas, alignment_options(config, raw_scene, "baseline")
            )
            actual, actual_transform = normalize_image(actual_path, canvas, alignment_options(config, raw_scene, "actual"))
            valid_mask, mask_info = build_valid_mask(config, raw_scene, canvas)
            if mask_info["unknown_ignore_sets"]:
                report["warnings"].append(
                    f"Scene {scene_name!r} references unknown ignore sets: "
                    f"{', '.join(mask_info['unknown_ignore_sets'])}"
                )
            if mask_info["valid_pixels"] <= 0:
                raise ValueError("Mask excludes every pixel")

            context = MetricContext(baseline, actual, changed_threshold, ssim_max_dimension)
            metrics = compute_metrics(context, valid_mask)
            thresholds = scene_thresholds(config, raw_scene)
            overall_passed, checks = evaluate_thresholds(metrics, thresholds)
            roi_masks, roi_warnings = build_roi_masks(config, raw_scene, valid_mask)
            report["warnings"].extend(f"Scene {scene_name!r}: {warning}" for warning in roi_warnings)
            roi_reports: dict[str, Any] = {}
            roi_failed = False
            for roi_name, roi_mask in roi_masks.items():
                roi_metric = compute_metrics(context, roi_mask)
                if roi_metric.get("status") == "empty":
                    roi_reports[roi_name] = {"status": "empty", "metrics": roi_metric, "checks": []}
                    continue
                roi_passed, roi_checks = evaluate_thresholds(roi_metric, roi_thresholds(config, raw_scene, roi_name))
                roi_failed = roi_failed or not roi_passed
                roi_reports[roi_name] = {
                    "status": "passed" if roi_passed else "failed",
                    "metrics": roi_metric,
                    "checks": roi_checks,
                }

            passed = overall_passed and (not fail_on_rois or not roi_failed)
            artifacts = create_artifacts(output_dir, scene_name, baseline, actual, context, valid_mask)
            scene_report.update(
                {
                    "status": "passed" if passed else "failed",
                    "baseline": input_description(baseline_path, baseline_transform),
                    "actual": input_description(actual_path, actual_transform),
                    "mask": mask_info,
                    "metrics": metrics,
                    "checks": checks,
                    "rois": roi_reports,
                    "artifacts": artifacts,
                }
            )
            report["summary"]["compared"] += 1
            report["summary"]["passed" if passed else "failed"] += 1
        except Exception as exc:
            scene_report.update({"status": "error", "error": str(exc)})
            report["summary"]["errors"] += 1
        report["scenes"].append(scene_report)

    report["status"] = report_status(report["summary"])
    safe_report = json_safe(report)
    json_path = output_dir / "report.json"
    markdown_path = output_dir / "report.md"
    json_path.write_text(json.dumps(safe_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    markdown_path.write_text(markdown_report(report), encoding="utf-8")

    print(f"Visual regression status: {report['status']}")
    print(
        "Scenes: "
        f"{report['summary']['compared']} compared, {report['summary']['passed']} passed, "
        f"{report['summary']['failed']} failed, {report['summary']['missing']} missing, "
        f"{report['summary']['errors']} errors"
    )
    print(f"JSON report: {json_path}")
    print(f"Markdown report: {markdown_path}")

    if report["summary"]["errors"]:
        return report, 2
    if args.strict_missing and report["summary"]["missing"]:
        return report, 2
    if report["summary"]["failed"] and not args.no_fail:
        return report, 1
    return report, 0


def make_selftest_images(directory: Path) -> tuple[Path, Path, Any, Any]:
    require_pillow()
    size = (160, 120)
    baseline = Image.new("RGB", size, "#203856")
    draw = ImageDraw.Draw(baseline)
    draw.rectangle((0, 0, 159, 42), fill="#78bfe8")
    draw.rectangle((0, 43, 159, 78), fill="#176a8a")
    draw.polygon([(0, 119), (0, 83), (159, 70), (159, 119)], fill="#57504a")
    draw.ellipse((58, 42, 102, 86), fill="#f4eee2", outline="#16181d", width=3)
    draw.line((42, 92, 118, 92), fill="#f5b841", width=5)
    draw.rectangle((4, 4, 36, 15), fill="#f8f8f8")

    changed = baseline.copy()
    changed_draw = ImageDraw.Draw(changed)
    changed_draw.rectangle((76, 48, 139, 95), fill="#d84a47")
    changed_draw.line((70, 40, 142, 104), fill="#fff07a", width=4)

    baseline_path = directory / "selftest-baseline.png"
    changed_path = directory / "selftest-actual.png"
    baseline.save(baseline_path)
    changed.save(changed_path)
    return baseline_path, changed_path, baseline, changed


def run_selftest(keep_output: Path | None = None) -> int:
    require_pillow()
    if keep_output is not None:
        keep_output.mkdir(parents=True, exist_ok=True)
        work_dir_context = None
        work_dir = keep_output
    else:
        work_dir_context = tempfile.TemporaryDirectory(
            prefix="visual-selftest-", dir=Path(__file__).resolve().parent
        )
        work_dir = Path(work_dir_context.name)

    try:
        baseline_path, actual_path, baseline, changed = make_selftest_images(work_dir)
        mask = Image.new("L", baseline.size, 255)
        mild = baseline.copy()
        mild.paste(changed.crop((76, 48, 108, 72)), (76, 48))

        same_metrics = compute_metrics(MetricContext(baseline, baseline, 4, 128), mask)
        mild_metrics = compute_metrics(MetricContext(baseline, mild, 4, 128), mask)
        changed_context = MetricContext(baseline, changed, 4, 128)
        changed_metrics = compute_metrics(changed_context, mask)

        assertions = {
            "MAE increases": same_metrics["mae"] < mild_metrics["mae"] < changed_metrics["mae"],
            "RMSE increases": same_metrics["rmse"] < mild_metrics["rmse"] < changed_metrics["rmse"],
            "PSNR decreases": same_metrics["psnr_db"] > mild_metrics["psnr_db"] > changed_metrics["psnr_db"],
            "SSIM decreases": same_metrics["ssim_global"] > mild_metrics["ssim_global"] > changed_metrics["ssim_global"],
            "changed ratio increases": (
                same_metrics["changed_pixel_ratio"]
                < mild_metrics["changed_pixel_ratio"]
                < changed_metrics["changed_pixel_ratio"]
            ),
            "histogram detects change": (
                same_metrics["histogram_distance"] < changed_metrics["histogram_distance"]
            ),
            "edge score detects change": (
                same_metrics["edge_structure_score"] > changed_metrics["edge_structure_score"]
            ),
            "visual score decreases": (
                same_metrics["visual_score"] > mild_metrics["visual_score"] > changed_metrics["visual_score"]
            ),
        }
        failed = [name for name, passed in assertions.items() if not passed]

        artifact_dir = work_dir / "artifacts"
        artifacts = create_artifacts(artifact_dir, "selftest", baseline, changed, changed_context, mask)
        expected = [artifact_dir / relative for relative in artifacts.values()]
        missing_artifacts = [str(path) for path in expected if not path.is_file()]
        if missing_artifacts:
            failed.append("artifact generation")

        # Verify a missing-input run can still produce both reports with exit code 0.
        missing_config = {
            "canvas": {"width": 160, "height": 120},
            "paths": {
                "baseline_dir": "missing-baselines",
                "actual_dir": "missing-actuals",
                "output_dir": "missing-report",
            },
            "scenes": {"missing-scene": {"baseline": "missing.png", "actual": "missing.png"}},
        }
        missing_config_path = work_dir / "missing-config.json"
        missing_config_path.write_text(json.dumps(missing_config), encoding="utf-8")
        missing_args = argparse.Namespace(
            baseline_dir=None,
            actual_dir=None,
            output_dir=None,
            scene=None,
            strict_missing=False,
            no_fail=False,
        )
        missing_report, missing_code = compare(missing_config_path, missing_args)
        missing_ok = (
            missing_code == 0
            and missing_report["status"] == "missing_inputs"
            and (work_dir / "missing-report" / "report.json").is_file()
            and (work_dir / "missing-report" / "report.md").is_file()
        )
        assertions["missing inputs are reported"] = missing_ok
        if not missing_ok:
            failed.append("missing inputs are reported")

        print("Self-test generated two 160x120 PNG inputs:")
        print(f"  {baseline_path}")
        print(f"  {actual_path}")
        print("Metric progression (same -> mild in-memory patch -> changed):")
        for key in ("mae", "rmse", "psnr_db", "ssim_global", "edge_structure_score", "histogram_distance", "visual_score"):
            print(
                f"  {key:24s} "
                f"{metric_display(same_metrics[key], 6):>12s} -> "
                f"{metric_display(mild_metrics[key], 6):>12s} -> "
                f"{metric_display(changed_metrics[key], 6):>12s}"
            )
        for name, passed in assertions.items():
            print(f"  [{'PASS' if passed else 'FAIL'}] {name}")

        if failed:
            print(f"Self-test failed: {', '.join(dict.fromkeys(failed))}", file=sys.stderr)
            return 1
        print("Self-test passed.")
        if keep_output is None:
            print("Temporary self-test files will be removed.")
        else:
            print(f"Self-test files kept at: {work_dir}")
        return 0
    finally:
        if work_dir_context is not None:
            work_dir_context.cleanup()


def doctor(config_path: Path | None) -> int:
    print(f"Python: {sys.version.split()[0]}")
    if _PIL_IMPORT_ERROR is not None:
        print(f"Pillow: MISSING ({_PIL_IMPORT_ERROR})")
        print("Install with: python -m pip install -r requirements.txt")
        return 2
    print(f"Pillow: {PIL.__version__}")
    if version_tuple(PIL.__version__) < MIN_PILLOW:
        print(f"Pillow is too old; require >= {'.'.join(map(str, MIN_PILLOW))}")
        return 2
    print("Pillow check: OK")
    if config_path is not None:
        try:
            config = load_json(config_path)
            scenes = config.get("scenes", {})
            if not isinstance(scenes, dict) or not scenes:
                raise ValueError("scenes must be a non-empty object")
            print(f"Config: OK ({len(scenes)} scenes) - {config_path}")
        except ValueError as exc:
            print(f"Config: ERROR - {exc}")
            return 2
    return 0


def default_config_path() -> Path:
    return Path(__file__).resolve().with_name(DEFAULT_CONFIG_NAME)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Compare web baseline PNGs with emulator PNGs and produce visual/metric reports."
    )
    parser.set_defaults(
        command="compare",
        config=default_config_path(),
        baseline_dir=None,
        actual_dir=None,
        output_dir=None,
        scene=None,
        strict_missing=False,
        no_fail=False,
    )
    subparsers = parser.add_subparsers(dest="command")

    compare_parser = subparsers.add_parser("compare", help="Run configured scene comparisons")
    compare_parser.add_argument("--config", type=Path, default=default_config_path())
    compare_parser.add_argument("--baseline-dir", type=Path, help="Override config baseline directory")
    compare_parser.add_argument("--actual-dir", type=Path, help="Override config actual screenshot directory")
    compare_parser.add_argument("--output-dir", type=Path, help="Override config output directory")
    compare_parser.add_argument("--scene", action="append", help="Compare only this named scene; repeat as needed")
    compare_parser.add_argument("--strict-missing", action="store_true", help="Return exit code 2 for missing inputs")
    compare_parser.add_argument("--no-fail", action="store_true", help="Return zero even when thresholds fail")

    selftest_parser = subparsers.add_parser("selftest", help="Generate two small PNGs and verify metric monotonicity")
    selftest_parser.add_argument("--keep-output", type=Path, help="Keep generated self-test files in this directory")

    doctor_parser = subparsers.add_parser("doctor", help="Check Pillow and config availability")
    doctor_parser.add_argument("--config", type=Path, default=default_config_path())

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    command = args.command or "compare"
    try:
        if command == "doctor":
            config_path = args.config.resolve() if args.config else None
            return doctor(config_path)
        require_pillow()
        if version_tuple(PIL.__version__) < MIN_PILLOW:
            print(
                f"Pillow >= {'.'.join(map(str, MIN_PILLOW))} is required; found {PIL.__version__}",
                file=sys.stderr,
            )
            return 2
        if command == "selftest":
            keep = args.keep_output.resolve() if args.keep_output else None
            return run_selftest(keep)
        if command == "compare":
            _, exit_code = compare(args.config.resolve(), args)
            return exit_code
        parser.error(f"Unknown command: {command}")
        return 2
    except (ValueError, OSError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
