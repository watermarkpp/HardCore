#!/usr/bin/env python3
"""Measure the real-client helmet pose for every male death cell.

The output is deliberately keyed by the same N..NW rows and F0..F3 columns
used by ``warrior_death.png``.  It is calibration evidence for a renderer,
not a request to invent a generic death transform.
"""

from __future__ import annotations

import hashlib
import json
import math
import statistics
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parents[1]
HELMET_LIBRARY = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Helmet.wil"
HAIR_LIBRARY = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"
BODY_ATLAS = ROOT / "assets/art/characters/warrior/male/warrior_death.png"
OUTPUT = ROOT / "outputs/resource_catalog/black_iron_helmet/death_pose_baseline.json"
ACCEPTANCE_ROOT = ROOT / "outputs/visual_acceptance/client_helmet_death_all_directions"
CONTACT_SHEET = ACCEPTANCE_ROOT / "all_six_appearances.png"
CELL = (192, 160)
DRAW_ORIGIN = (64, 80)
HELMET_STRIDE = 600
HELMET_APPEARANCES = 6
HAIR_STRIDE = 2224
HAIR_APPEARANCE = 2
DEATH_START = 536
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
DIRECTION_YAWS = [180.0, 135.0, 90.0, 45.0, 0.0, -45.0, -90.0, -135.0]
CAMERA_ELEVATION_DEGREES = math.degrees(math.atan2(3.0, 5.0))
FRAMES = 4

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = math.floor(position)
    high = math.ceil(position)
    if low == high:
        return float(ordered[low])
    return ordered[low] * (high - position) + ordered[high] * (position - low)


def rounded(value: float) -> float:
    return round(float(value), 4)


def summary(values: list[float]) -> dict:
    return {
        "median": rounded(statistics.median(values)),
        "p25": rounded(percentile(values, 0.25)),
        "p75": rounded(percentile(values, 0.75)),
        "min": rounded(min(values)),
        "max": rounded(max(values)),
    }


def axial_summary(values: list[float]) -> dict:
    """Summarize unoriented axes where -90 and +90 degrees are equivalent."""
    doubled = [math.radians(value * 2.0) for value in values]
    cosine = sum(math.cos(value) for value in doubled) / len(doubled)
    sine = sum(math.sin(value) for value in doubled) / len(doubled)
    mean = math.degrees(math.atan2(sine, cosine)) * 0.5
    concentration = math.sqrt(cosine * cosine + sine * sine)
    return {
        "axialMean": rounded(mean),
        "concentration": rounded(concentration),
        "samples": [rounded(value) for value in values],
    }


def normalize_axis_delta(value: float) -> float:
    while value <= -90.0:
        value += 180.0
    while value > 90.0:
        value -= 180.0
    return value


def angular_distance(first: float, second: float) -> float:
    return abs((first - second + 180.0) % 360.0 - 180.0)


def projected_up_degrees(yaw_degrees: float, fall_degrees: float) -> float:
    """Project the helmet's local up vector through the renderer camera."""
    yaw = math.radians(yaw_degrees)
    fall = math.radians(fall_degrees)
    elevation = math.radians(CAMERA_ELEVATION_DEGREES)
    x = math.sin(yaw) * math.sin(fall)
    y = math.cos(fall)
    z = math.cos(yaw) * math.sin(fall)
    screen_up = math.cos(elevation) * y - math.sin(elevation) * z
    return math.degrees(math.atan2(x, screen_up))


def solve_fall_degrees(yaw_degrees: float, target_screen_degrees: float) -> tuple[float, float]:
    candidates = [value * 0.5 for value in range(-220, 1)]
    best = min(
        candidates,
        key=lambda value: angular_distance(projected_up_degrees(yaw_degrees, value), target_screen_degrees),
    )
    error = angular_distance(projected_up_degrees(yaw_degrees, best), target_screen_degrees)
    return best, error


def decoded_cell(data: bytes, palette: list, offsets: list[int], index: int) -> Image.Image:
    sprite, meta = decode_sprite(data, offsets[index], palette)
    cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
    cell.alpha_composite(
        sprite.convert("RGBA"),
        (DRAW_ORIGIN[0] + int(meta["x"]), DRAW_ORIGIN[1] + int(meta["y"])),
    )
    if cell.getchannel("A").getbbox() is None:
        raise ValueError(f"Client source frame is empty: {index}")
    return cell


def mask_features(image: Image.Image) -> dict:
    alpha = np.asarray(image.getchannel("A"))
    ys, xs = np.nonzero(alpha)
    if len(xs) < 2:
        raise ValueError("Not enough opaque pixels to measure pose")
    x0, x1 = int(xs.min()), int(xs.max()) + 1
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    weights = alpha[ys, xs].astype(np.float64) / 255.0
    centre_x = float(np.average(xs, weights=weights))
    centre_y = float(np.average(ys, weights=weights))
    centred = np.column_stack((xs - centre_x, ys - centre_y)).astype(np.float64)
    covariance = np.cov(centred, rowvar=False, aweights=weights)
    eigenvalues, eigenvectors = np.linalg.eigh(covariance)
    major = eigenvectors[:, int(np.argmax(eigenvalues))]
    angle = math.degrees(math.atan2(float(major[1]), float(major[0])))
    while angle <= -90.0:
        angle += 180.0
    while angle > 90.0:
        angle -= 180.0
    major_value = max(float(eigenvalues.max()), 1e-9)
    minor_value = max(float(eigenvalues.min()), 1e-9)
    return {
        "bbox": [x0, y0, x1, y1],
        "width": x1 - x0,
        "height": y1 - y0,
        "centroid": [centre_x, centre_y],
        "principalAxisDegrees": angle,
        "elongation": math.sqrt(major_value / minor_value),
        "opaquePixels": int(len(xs)),
    }


def body_cell(atlas: Image.Image, direction: int, frame: int) -> Image.Image:
    return atlas.crop(
        (
            frame * CELL[0],
            direction * CELL[1],
            (frame + 1) * CELL[0],
            (direction + 1) * CELL[1],
        )
    )


def dim_body(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    rgb = ImageEnhance.Brightness(rgba.convert("RGB")).enhance(0.32)
    result = rgb.convert("RGBA")
    result.putalpha(rgba.getchannel("A").point(lambda value: round(value * 0.58)))
    return result


def composite_atlas(body: Image.Image, cells: dict[tuple[int, int], Image.Image]) -> Image.Image:
    atlas = Image.new("RGBA", (CELL[0] * FRAMES, CELL[1] * len(DIRECTIONS)), (10, 11, 14, 255))
    for direction in range(len(DIRECTIONS)):
        for frame in range(FRAMES):
            tile = Image.new("RGBA", CELL, (10, 11, 14, 255))
            tile.alpha_composite(dim_body(body_cell(body, direction, frame)))
            tile.alpha_composite(cells[(direction, frame)])
            atlas.alpha_composite(tile, (frame * CELL[0], direction * CELL[1]))
    return atlas


def main() -> None:
    for required in (HELMET_LIBRARY, HAIR_LIBRARY, BODY_ATLAS):
        if not required.exists():
            raise FileNotFoundError(required)
    helmet_data, helmet_palette, helmet_offsets, helmet_info = read_library(HELMET_LIBRARY)
    hair_data, hair_palette, hair_offsets, hair_info = read_library(HAIR_LIBRARY)
    if int(helmet_info["image_count"]) != HELMET_STRIDE * HELMET_APPEARANCES:
        raise AssertionError("Helmet.wil no longer contains six 600-frame appearances")
    if int(hair_info["image_count"]) <= HAIR_APPEARANCE * HAIR_STRIDE + DEATH_START + 7 * 8 + 3:
        raise AssertionError("Hair.wil does not contain the expected death anchor range")
    body = Image.open(BODY_ATLAS).convert("RGBA")
    if body.size != (CELL[0] * FRAMES, CELL[1] * len(DIRECTIONS)):
        raise AssertionError(f"Unexpected warrior death atlas size: {body.size}")

    appearance_cells: list[dict[tuple[int, int], Image.Image]] = [dict() for _ in range(HELMET_APPEARANCES)]
    raw_features: dict[tuple[int, int], list[dict]] = {}
    records: list[dict] = []
    for direction, direction_name in enumerate(DIRECTIONS):
        first_features: list[dict] = []
        for appearance in range(HELMET_APPEARANCES):
            first_index = appearance * HELMET_STRIDE + DEATH_START + direction * 8
            first = decoded_cell(helmet_data, helmet_palette, helmet_offsets, first_index)
            first_features.append(mask_features(first))
        for frame in range(FRAMES):
            samples: list[dict] = []
            for appearance in range(HELMET_APPEARANCES):
                index = appearance * HELMET_STRIDE + DEATH_START + direction * 8 + frame
                cell = decoded_cell(helmet_data, helmet_palette, helmet_offsets, index)
                appearance_cells[appearance][(direction, frame)] = cell
                measured = mask_features(cell)
                baseline = first_features[appearance]
                measured["appearance"] = appearance
                measured["sourceIndex"] = index
                measured["widthFromF0"] = measured["width"] / baseline["width"]
                measured["heightFromF0"] = measured["height"] / baseline["height"]
                measured["centroidDeltaFromF0"] = [
                    measured["centroid"][0] - baseline["centroid"][0],
                    measured["centroid"][1] - baseline["centroid"][1],
                ]
                measured["axisDeltaFromF0"] = normalize_axis_delta(
                    measured["principalAxisDegrees"] - baseline["principalAxisDegrees"]
                )
                samples.append(measured)
            raw_features[(direction, frame)] = samples
            hair_index = HAIR_APPEARANCE * HAIR_STRIDE + DEATH_START + direction * 8 + frame
            hair = mask_features(decoded_cell(hair_data, hair_palette, hair_offsets, hair_index))
            body_box = body_cell(body, direction, frame).getchannel("A").getbbox()
            if body_box is None:
                raise AssertionError(f"Body death cell is empty: {direction_name} F{frame}")
            measured_body = mask_features(body_cell(body, direction, frame))
            centre_x = [sample["centroid"][0] for sample in samples]
            centre_y = [sample["centroid"][1] for sample in samples]
            median_centre = [statistics.median(centre_x), statistics.median(centre_y)]
            body_to_helmet = [
                median_centre[0] - measured_body["centroid"][0],
                median_centre[1] - measured_body["centroid"][1],
            ]
            body_to_helmet_degrees = math.degrees(math.atan2(body_to_helmet[0], -body_to_helmet[1]))
            body_to_hair = [
                hair["centroid"][0] - measured_body["centroid"][0],
                hair["centroid"][1] - measured_body["centroid"][1],
            ]
            body_to_hair_degrees = math.degrees(math.atan2(body_to_hair[0], -body_to_hair[1]))
            body_axis_radians = math.radians(measured_body["principalAxisDegrees"])
            body_up = [math.cos(body_axis_radians), math.sin(body_axis_radians)]
            if body_up[0] * body_to_hair[0] + body_up[1] * body_to_hair[1] < 0.0:
                body_up = [-body_up[0], -body_up[1]]
            body_up_degrees = math.degrees(math.atan2(body_up[0], -body_up[1]))
            record = {
                "direction": direction_name,
                "directionRow": direction,
                "frame": frame,
                "bodyCell": [frame, direction],
                "bodyOpaqueBox": list(body_box),
                "bodyCentroid": [rounded(value) for value in measured_body["centroid"]],
                "bodyPrincipalAxis": axial_summary([measured_body["principalAxisDegrees"]]),
                "bodyToHelmetVector": [rounded(value) for value in body_to_helmet],
                "bodyToHelmetScreenDegrees": rounded(body_to_helmet_degrees),
                "bodyToHairVector": [rounded(value) for value in body_to_hair],
                "bodyToHairScreenDegrees": rounded(body_to_hair_degrees),
                "bodyUpVector": [rounded(value) for value in body_up],
                "bodyUpScreenDegrees": rounded(body_up_degrees),
                "hairAnchorSourceIndex": hair_index,
                "hairAnchorOpaqueBox": hair["bbox"],
                "hairAnchorCentroid": [rounded(value) for value in hair["centroid"]],
                "clientAppearanceCount": len(samples),
                "clientHelmetCentroid": {
                    "x": summary(centre_x),
                    "y": summary(centre_y),
                },
                "clientHelmetWidth": summary([float(sample["width"]) for sample in samples]),
                "clientHelmetHeight": summary([float(sample["height"]) for sample in samples]),
                "clientHelmetOpaquePixels": summary([float(sample["opaquePixels"]) for sample in samples]),
                "principalAxisDegrees": axial_summary([sample["principalAxisDegrees"] for sample in samples]),
                "axisDeltaFromF0": axial_summary([sample["axisDeltaFromF0"] for sample in samples]),
                "elongation": summary([sample["elongation"] for sample in samples]),
                "widthFromF0": summary([sample["widthFromF0"] for sample in samples]),
                "heightFromF0": summary([sample["heightFromF0"] for sample in samples]),
                "centroidDeltaFromF0": {
                    "x": summary([sample["centroidDeltaFromF0"][0] for sample in samples]),
                    "y": summary([sample["centroidDeltaFromF0"][1] for sample in samples]),
                },
                "samples": samples,
            }
            records.append(record)

    observable_by_frame: dict[int, list[float]] = {frame: [] for frame in range(FRAMES)}
    for record in records:
        yaw = DIRECTION_YAWS[int(record["directionRow"])]
        fall, _ = solve_fall_degrees(yaw, float(record["bodyToHairScreenDegrees"]))
        if abs(math.sin(math.radians(yaw))) > 0.25:
            observable_by_frame[int(record["frame"])].append(fall)
    fallback_fall = {
        frame: statistics.median(values)
        for frame, values in observable_by_frame.items()
    }
    fallback_fall[0] = 0.0
    for record in records:
        yaw = DIRECTION_YAWS[int(record["directionRow"])]
        frame = int(record["frame"])
        if frame == 0:
            fall = 0.0
            fit_error = angular_distance(0.0, float(record["bodyToHairScreenDegrees"]))
            source = "standing death start"
        elif abs(math.sin(math.radians(yaw))) <= 0.25:
            fall = fallback_fall[frame]
            fit_error = angular_distance(
                projected_up_degrees(yaw, fall),
                float(record["bodyToHairScreenDegrees"]),
            )
            source = "camera-axis-degenerate; median of the six observable direction rows for this frame"
        else:
            fall, fit_error = solve_fall_degrees(yaw, float(record["bodyToHairScreenDegrees"]))
            source = "inverted from the same-cell Hair.wil body-to-head screen vector"
        record["recommendedGodotPose"] = {
            "yawDegrees": rounded(yaw),
            "fallDegrees": rounded(fall),
            "targetScreenDegrees": record["bodyToHairScreenDegrees"],
            "projectedScreenDegrees": rounded(projected_up_degrees(yaw, fall)),
            "fitErrorDegrees": rounded(fit_error),
            "source": source,
        }

    ACCEPTANCE_ROOT.mkdir(parents=True, exist_ok=True)
    rendered: list[Image.Image] = []
    appearance_paths: list[str] = []
    for appearance, cells in enumerate(appearance_cells):
        atlas = composite_atlas(body, cells)
        target = ACCEPTANCE_ROOT / f"appearance_{appearance}.png"
        atlas.save(target)
        rendered.append(atlas)
        appearance_paths.append(target.relative_to(ROOT).as_posix())
    half_size = (rendered[0].width // 2, rendered[0].height // 2)
    sheet = Image.new("RGBA", (half_size[0] * 3, half_size[1] * 2), (10, 11, 14, 255))
    for appearance, atlas in enumerate(rendered):
        preview = atlas.resize(half_size, Image.Resampling.NEAREST)
        sheet.alpha_composite(preview, ((appearance % 3) * half_size[0], (appearance // 3) * half_size[1]))
    sheet.save(CONTACT_SHEET)

    payload = {
        "schemaVersion": 1,
        "source": HELMET_LIBRARY.relative_to(ROOT).as_posix(),
        "sourceSha256": sha256(HELMET_LIBRARY),
        "hairAnchorSource": HAIR_LIBRARY.relative_to(ROOT).as_posix(),
        "hairAnchorSourceSha256": sha256(HAIR_LIBRARY),
        "bodyAtlas": BODY_ATLAS.relative_to(ROOT).as_posix(),
        "bodyAtlasSha256": sha256(BODY_ATLAS),
        "cell": list(CELL),
        "directionOrder": DIRECTIONS,
        "framesPerDirection": FRAMES,
        "rendererCamera": {
            "position": [0.0, 3.0, 5.0],
            "lookAt": [0.0, 0.0, 0.0],
            "orthographic": True,
            "elevationDegrees": rounded(CAMERA_ELEVATION_DEGREES),
        },
        "mappingRule": "Every record is the same direction row and death-frame column in warrior_death.png, Helmet.wil and Hair.wil.",
        "rendererPolicy": "A renderer must consume all 32 records independently; it may not copy one direction's death pose into another direction.",
        "appearanceAtlases": appearance_paths,
        "contactSheet": CONTACT_SHEET.relative_to(ROOT).as_posix(),
        "records": records,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "CLIENT_HELMET_DEATH_POSE_BASELINE_PASS "
        f"records={len(records)} samples={len(records) * HELMET_APPEARANCES} "
        f"report={OUTPUT.relative_to(ROOT).as_posix()} "
        f"sheet={CONTACT_SHEET.relative_to(ROOT).as_posix()}"
    )


if __name__ == "__main__":
    main()
