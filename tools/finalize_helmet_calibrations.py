#!/usr/bin/env python3
"""Finalize user-authored helmet calibration drafts into runtime assets.

The drafts and their high-resolution PNGs are immutable inputs. Every runtime
sprite is resized directly from its selected original cutout with one
premultiplied-alpha Lanczos pass. Existing low-resolution helmet atlases are
used only as motion/anchor evidence; their pixels never enter the output.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops


DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
ACTIONS = ("idle", "walk", "attack", "cast", "hit", "death")
HIDDEN_HELMET_ACTIONS = frozenset({"death"})
FRAME_SIZE = (192, 160)
AUTHORED_WORLD_DISPLAY_SCALE = 0.08
PAPER_PREVIEW_SCALE = 1.22
PAPER_COMPOSITION_ORIGIN = (167.519989013672, 91.2200164794922)
PAPER_CALIBRATION_CANVAS = (540, 340)
NORMAL_ASPECT_LIMIT = 0.08
DEATH_ASPECT_LIMIT = 0.18
PAPER_REFERENCE_SIZES = {
    146: (24, 28),
    147: (32, 41),
    148: (32, 41),
    149: (32, 40),
    150: (52, 42),
    151: (28, 32),
    218: (48, 48),
    224: (32, 40),
    228: (32, 42),
    232: (32, 41),
    236: (32, 41),
    240: (32, 41),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def write_json(path: Path, value: Any) -> None:
    path.write_bytes(json_bytes(value))


def res_path(root: Path, value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError(f"not a res:// path: {value}")
    return root / Path(value.removeprefix("res://"))


def to_res(root: Path, path: Path) -> str:
    return "res://" + path.relative_to(root).as_posix()


def rgba(path: Path) -> Image.Image:
    return Image.open(path).convert("RGBA")


def alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("transparent source image")
    return bbox


def crop_alpha(image: Image.Image) -> Image.Image:
    return image.crop(alpha_bbox(image))


def rgba_sha(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def premultiplied_lanczos_resize(
    source: Image.Image, target_size: tuple[int, int]
) -> Image.Image:
    """Resize once from the original RGBA pixels without transparent RGB halos."""
    width = max(1, int(target_size[0]))
    height = max(1, int(target_size[1]))
    red, green, blue, alpha = source.convert("RGBA").split()
    premultiplied = [
        ImageChops.multiply(channel, alpha)
        for channel in (red, green, blue)
    ]
    resized_rgb = [
        channel.resize((width, height), Image.Resampling.LANCZOS)
        for channel in premultiplied
    ]
    resized_alpha = alpha.resize((width, height), Image.Resampling.LANCZOS)
    alpha_bytes = resized_alpha.tobytes()
    rgb_bytes = [channel.tobytes() for channel in resized_rgb]
    output = bytearray(width * height * 4)
    for index, alpha_value in enumerate(alpha_bytes):
        output_index = index * 4
        if alpha_value <= 5:
            continue
        output[output_index] = min(
            255, int(round(rgb_bytes[0][index] * 255.0 / alpha_value))
        )
        output[output_index + 1] = min(
            255, int(round(rgb_bytes[1][index] * 255.0 / alpha_value))
        )
        output[output_index + 2] = min(
            255, int(round(rgb_bytes[2][index] * 255.0 / alpha_value))
        )
        output[output_index + 3] = alpha_value
    return Image.frombytes("RGBA", (width, height), bytes(output))


def premultiplied_affine_to_cell(
    source: Image.Image,
    target_size: tuple[int, int],
    rotation_degrees: float,
    center: tuple[float, float],
) -> Image.Image:
    """Apply scale, rotation and placement from original pixels in one pass."""
    source = source.convert("RGBA")
    target_width = max(1, int(target_size[0]))
    target_height = max(1, int(target_size[1]))
    scale_x = target_width / source.width
    scale_y = target_height / source.height
    radians = math.radians(rotation_degrees)
    cosine = math.cos(radians)
    sine = math.sin(radians)
    inverse = (
        cosine / scale_x,
        sine / scale_x,
        source.width / 2.0
        - cosine * center[0] / scale_x
        - sine * center[1] / scale_x,
        -sine / scale_y,
        cosine / scale_y,
        source.height / 2.0
        + sine * center[0] / scale_y
        - cosine * center[1] / scale_y,
    )
    red, green, blue, alpha = source.split()
    premultiplied = [
        ImageChops.multiply(channel, alpha)
        for channel in (red, green, blue)
    ]
    transformed_rgb = [
        channel.transform(
            FRAME_SIZE,
            Image.Transform.AFFINE,
            inverse,
            resample=Image.Resampling.BICUBIC,
            fillcolor=0,
        )
        for channel in premultiplied
    ]
    transformed_alpha = alpha.transform(
        FRAME_SIZE,
        Image.Transform.AFFINE,
        inverse,
        resample=Image.Resampling.BICUBIC,
        fillcolor=0,
    )
    alpha_bytes = transformed_alpha.tobytes()
    rgb_bytes = [channel.tobytes() for channel in transformed_rgb]
    output = bytearray(FRAME_SIZE[0] * FRAME_SIZE[1] * 4)
    for index, alpha_value in enumerate(alpha_bytes):
        output_index = index * 4
        if alpha_value <= 5:
            continue
        output[output_index] = min(
            255, int(round(rgb_bytes[0][index] * 255.0 / alpha_value))
        )
        output[output_index + 1] = min(
            255, int(round(rgb_bytes[1][index] * 255.0 / alpha_value))
        )
        output[output_index + 2] = min(
            255, int(round(rgb_bytes[2][index] * 255.0 / alpha_value))
        )
        output[output_index + 3] = alpha_value
    return Image.frombytes("RGBA", FRAME_SIZE, bytes(output))


def resolved_pose_transform(
    draft: dict[str, Any],
    action: str,
    target_direction: str,
    frame: int,
) -> dict[str, Any]:
    direction = draft["directions"][target_direction]
    result: dict[str, Any] = {
        "source_row": int(direction["source_row"]),
        "offset": [0.0, 0.0],
        "scale_x_percent": int(direction["scale_percent"]),
        "scale_y_percent": int(direction["scale_percent"]),
        "rotation_degrees": 0.0,
    }
    stored = (
        draft.get("poseTransforms", {})
        .get(action, {})
        .get(target_direction, {})
        .get(str(frame), {})
    )
    if isinstance(stored, dict):
        result.update(stored)
    source_row = int(result["source_row"])
    scale_x = int(result["scale_x_percent"])
    scale_y = int(result["scale_y_percent"])
    rotation = float(result["rotation_degrees"])
    offset = result["offset"]
    if source_row not in range(8):
        raise ValueError(
            f"invalid pose source row: {action}/{target_direction}/{frame}"
        )
    if (
        scale_x < 5
        or scale_x > 400
        or scale_y < 5
        or scale_y > 400
        or scale_x % 5
        or scale_y % 5
    ):
        raise ValueError(
            f"invalid pose scale: {action}/{target_direction}/{frame}"
        )
    if (
        not math.isfinite(rotation)
        or not math.isclose(rotation / 5.0, round(rotation / 5.0))
        or not isinstance(offset, list)
        or len(offset) < 2
        or not all(math.isfinite(float(value)) for value in offset[:2])
        or not all(
            math.isclose(float(value) * 2.0, round(float(value) * 2.0))
            for value in offset[:2]
        )
    ):
        raise ValueError(
            f"invalid pose transform: {action}/{target_direction}/{frame}"
        )
    return {
        "source_row": source_row,
        "offset": [float(offset[0]), float(offset[1])],
        "scale_x_percent": scale_x,
        "scale_y_percent": scale_y,
        "rotation_degrees": rotation,
    }


@dataclass(frozen=True)
class MaskStats:
    bbox: tuple[int, int, int, int]
    alpha_mass: float
    std_x: float
    std_y: float


def mask_stats(image: Image.Image) -> MaskStats:
    alpha = image.getchannel("A")
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("empty placement mask")
    cropped = alpha.crop(bbox)
    mass = 0.0
    moment_x = 0.0
    moment_y = 0.0
    pixels = cropped.tobytes()
    for local_y in range(cropped.height):
        for local_x in range(cropped.width):
            weight = pixels[local_y * cropped.width + local_x] / 255.0
            if weight <= 0.0:
                continue
            x = bbox[0] + local_x + 0.5
            y = bbox[1] + local_y + 0.5
            mass += weight
            moment_x += x * weight
            moment_y += y * weight
    center_x = moment_x / mass
    center_y = moment_y / mass
    variance_x = 0.0
    variance_y = 0.0
    for local_y in range(cropped.height):
        for local_x in range(cropped.width):
            weight = pixels[local_y * cropped.width + local_x] / 255.0
            if weight <= 0.0:
                continue
            x = bbox[0] + local_x + 0.5
            y = bbox[1] + local_y + 0.5
            variance_x += (x - center_x) ** 2 * weight
            variance_y += (y - center_y) ** 2 * weight
    std_x = math.sqrt(max(1.0e-6, variance_x / mass))
    std_y = math.sqrt(max(1.0e-6, variance_y / mass))
    return MaskStats(bbox, mass, std_x, std_y)


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def action_deformation(
    reference: MaskStats, frame: MaskStats, action: str
) -> tuple[float, float]:
    """Return bounded X/Y motion deformation derived only from pose evidence."""
    if action == "idle":
        uniform_limit = 0.05
        aspect_limit = 0.04
    elif action == "walk":
        uniform_limit = 0.08
        aspect_limit = 0.05
    elif action == "death":
        uniform_limit = 0.18
        aspect_limit = DEATH_ASPECT_LIMIT
    else:
        uniform_limit = 0.12
        aspect_limit = NORMAL_ASPECT_LIMIT
    uniform = math.sqrt(frame.alpha_mass / reference.alpha_mass)
    uniform = clamp(uniform, 1.0 - uniform_limit, 1.0 + uniform_limit)
    raw_ratio = (frame.std_x / reference.std_x) / (
        frame.std_y / reference.std_y
    )
    log_ratio = clamp(
        0.5 * math.log(max(1.0e-6, raw_ratio)),
        -aspect_limit,
        aspect_limit,
    )
    return uniform * math.exp(log_ratio), uniform * math.exp(-log_ratio)


def pivot_for(direction_record: dict[str, Any], action: str, frame: int) -> tuple[float, float]:
    frames = direction_record["pivotByActionFrame"][action]
    value = frames[min(frame, len(frames) - 1)]
    return float(value[0]), float(value[1])


def atlas_cell(
    atlas: Image.Image, source_row: int, frame: int
) -> Image.Image:
    width, height = FRAME_SIZE
    return atlas.crop(
        (frame * width, source_row * height, (frame + 1) * width, (source_row + 1) * height)
    )


def paste_with_anchor(
    cell: Image.Image,
    sprite: Image.Image,
    source_anchor_fraction: tuple[float, float],
    pivot: tuple[float, float],
) -> tuple[int, int]:
    anchor_x = source_anchor_fraction[0] * sprite.width
    anchor_y = source_anchor_fraction[1] * sprite.height
    left = int(round(pivot[0] - anchor_x))
    top = int(round(pivot[1] - anchor_y))
    cell.alpha_composite(sprite, (left, top))
    return left, top


def source_cutouts(
    root: Path, draft: dict[str, Any]
) -> tuple[dict[int, Image.Image], dict[int, dict[str, str]]]:
    source = draft["source"]
    direction_order = [str(value) for value in source["directionOrder"]]
    prepared = source.get("preparedDirectionFiles", {})
    prepared_sha = source.get("preparedDirectionSha256", {})
    result: dict[int, Image.Image] = {}
    provenance: dict[int, dict[str, str]] = {}
    if prepared:
        for row, direction in enumerate(direction_order):
            path = res_path(root, prepared[direction])
            actual_sha = sha256(path)
            if actual_sha.lower() != str(prepared_sha[direction]).lower():
                raise ValueError(f"prepared direction hash changed: {path}")
            result[row] = crop_alpha(rgba(path))
            provenance[row] = {
                "direction": direction,
                "path": to_res(root, path),
                "sha256": actual_sha,
            }
        return result, provenance
    sheet_path = res_path(root, source["sheet"])
    actual_sheet_sha = sha256(sheet_path)
    if actual_sheet_sha.lower() != str(source["sheetSha256"]).lower():
        raise ValueError(f"source sheet hash changed: {sheet_path}")
    sheet = rgba(sheet_path)
    columns, rows = (int(value) for value in source["grid"])
    for row in range(columns * rows):
        column = row % columns
        line = row // columns
        x0 = round(column * sheet.width / columns)
        x1 = round((column + 1) * sheet.width / columns)
        y0 = round(line * sheet.height / rows)
        y1 = round((line + 1) * sheet.height / rows)
        result[row] = crop_alpha(sheet.crop((x0, y0, x1, y1)))
        provenance[row] = {
            "direction": direction_order[row],
            "path": to_res(root, sheet_path),
            "sha256": actual_sheet_sha,
            "sheetCell": f"{column},{line}",
        }
    return result, provenance


def presentation_source(
    root: Path,
    draft: dict[str, Any],
    cutouts: dict[int, Image.Image],
    role: str,
) -> tuple[Image.Image, dict[str, Any]]:
    calibration = draft["presentationCalibration"][role]
    variant = str(calibration.get("source_variant", ""))
    if variant:
        path_value = draft["source"]["preparedPresentationFiles"][role]
        expected = draft["source"]["preparedPresentationSha256"][role]
        path = res_path(root, path_value)
        actual = sha256(path)
        if actual.lower() != str(expected).lower():
            raise ValueError(f"presentation source hash changed: {path}")
        return crop_alpha(rgba(path)), {
            "sourceVariant": variant,
            "path": path_value,
            "sha256": actual,
        }
    source_row = int(calibration["source_row"])
    direction = str(draft["source"]["directionOrder"][source_row])
    return cutouts[source_row].copy(), {
        "sourceVariant": "direction",
        "sourceRow": source_row,
        "sourceDirection": direction,
    }


def fit_inside(source: Image.Image, bounds: tuple[int, int]) -> tuple[int, int]:
    factor = min(bounds[0] / source.width, bounds[1] / source.height)
    return (
        max(1, int(round(source.width * factor))),
        max(1, int(round(source.height * factor))),
    )


def save_png(image: Image.Image, path: Path) -> dict[str, Any]:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)
    return {
        "path": path,
        "size": [image.width, image.height],
        "fileSha256": sha256(path),
        "rgbaSha256": rgba_sha(image),
    }


def paper_draw_offset(paper: dict[str, Any]) -> list[float]:
    offset = paper["offset"]
    return [
        round((float(offset[0]) - PAPER_COMPOSITION_ORIGIN[0]) / PAPER_PREVIEW_SCALE, 3),
        round((float(offset[1]) - PAPER_COMPOSITION_ORIGIN[1]) / PAPER_PREVIEW_SCALE, 3),
    ]


def transparent_safe_border(image: Image.Image, pixels: int = 1) -> Image.Image:
    bordered = Image.new(
        "RGBA",
        (image.width + pixels * 2, image.height + pixels * 2),
        (0, 0, 0, 0),
    )
    bordered.alpha_composite(image, (pixels, pixels))
    return bordered


def build_world_atlases(
    root: Path,
    draft: dict[str, Any],
    visual_asset: dict[str, Any],
    cutouts: dict[int, Image.Image],
    output_dir: Path,
) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, Any]]:
    if bool(
        draft.get("previewPolicy", {}).get(
            "poseFrameIndependentSource", False
        )
    ):
        return build_pose_authored_world_atlases(
            root, draft, visual_asset, cutouts, output_dir
        )
    mapping_by_row: dict[int, dict[str, Any]] = {}
    for target_direction, record in draft["directions"].items():
        source_row = int(record["source_row"])
        if source_row in mapping_by_row:
            if int(mapping_by_row[source_row]["scale_percent"]) != int(
                record["scale_percent"]
            ):
                raise ValueError(f"one source row has conflicting scales: {source_row}")
        mapping_by_row[source_row] = record
    if set(mapping_by_row) != set(range(8)):
        raise ValueError("final calibration must map every source row exactly once")

    direction_order = [str(value) for value in draft["source"]["directionOrder"]]
    resized_cache: dict[tuple[int, int, int], Image.Image] = {}
    derived_paths: dict[str, str] = {}
    source_sha: dict[str, str] = {}
    derived_sha: dict[str, str] = {}
    action_metrics: dict[str, Any] = {}

    for action in ACTIONS:
        evidence_path_value = visual_asset["directions"]["N"]["layers"]["helmet_front"][action]
        evidence_path = res_path(root, evidence_path_value)
        evidence = rgba(evidence_path)
        frame_count = evidence.width // FRAME_SIZE[0]
        if evidence.height != FRAME_SIZE[1] * 8 or frame_count <= 0:
            raise ValueError(f"invalid base atlas: {evidence_path}")
        output = Image.new("RGBA", evidence.size, (0, 0, 0, 0))
        action_rows: dict[str, Any] = {}

        for source_row in range(8):
            semantic_direction = direction_order[source_row]
            direction_record = visual_asset["directions"][semantic_direction]
            placement_row = int(direction_record["source_row"])
            original = cutouts[source_row]
            original_bbox = alpha_bbox(original)
            source_width = original_bbox[2] - original_bbox[0]
            source_height = original_bbox[3] - original_bbox[1]

            idle_evidence_path = res_path(
                root,
                direction_record["layers"]["helmet_front"]["idle"],
            )
            idle_evidence = rgba(idle_evidence_path)
            reference_cell = atlas_cell(idle_evidence, placement_row, 0)
            reference_stats = mask_stats(reference_cell)
            reference_bbox = reference_stats.bbox
            reference_width = reference_bbox[2] - reference_bbox[0]
            reference_height = reference_bbox[3] - reference_bbox[1]
            reference_pivot = pivot_for(direction_record, "idle", 0)
            anchor_fraction = (
                (reference_pivot[0] - reference_bbox[0]) / reference_width,
                (reference_pivot[1] - reference_bbox[1]) / reference_height,
            )
            percent = int(mapping_by_row[source_row]["scale_percent"])
            calibrated_area = (
                reference_width
                * reference_height
                * (float(percent) / 100.0) ** 2
            )
            base_scale = math.sqrt(
                calibrated_area / max(1.0, source_width * source_height)
            )
            row_frames: list[dict[str, Any]] = []

            for frame in range(frame_count):
                frame_cell = atlas_cell(evidence, placement_row, frame)
                frame_stats = mask_stats(frame_cell)
                deform_x, deform_y = action_deformation(
                    reference_stats, frame_stats, action
                )
                target_size = (
                    max(1, int(round(source_width * base_scale * deform_x))),
                    max(1, int(round(source_height * base_scale * deform_y))),
                )
                cache_key = (source_row, target_size[0], target_size[1])
                if cache_key not in resized_cache:
                    resized_cache[cache_key] = premultiplied_lanczos_resize(
                        original, target_size
                    )
                sprite = resized_cache[cache_key]
                pivot = pivot_for(direction_record, action, frame)
                destination_cell = Image.new(
                    "RGBA", FRAME_SIZE, (0, 0, 0, 0)
                )
                left, top = paste_with_anchor(
                    destination_cell, sprite, anchor_fraction, pivot
                )
                output.alpha_composite(
                    destination_cell,
                    (frame * FRAME_SIZE[0], source_row * FRAME_SIZE[1]),
                )
                row_frames.append(
                    {
                        "frame": frame,
                        "size": list(target_size),
                        "pivot": [round(pivot[0], 3), round(pivot[1], 3)],
                        "topLeft": [left, top],
                        "deformation": [
                            round(deform_x, 5),
                            round(deform_y, 5),
                        ],
                    }
                )
            action_rows[str(source_row)] = {
                "sourceDirection": semantic_direction,
                "sourceAspect": round(source_width / source_height, 6),
                "referenceEnvelope": list(reference_bbox),
                "anchorFraction": [
                    round(anchor_fraction[0], 6),
                    round(anchor_fraction[1], 6),
                ],
                "calibratedPercent": percent,
                "frames": row_frames,
            }

        if action in HIDDEN_HELMET_ACTIONS:
            output = Image.new("RGBA", evidence.size, (0, 0, 0, 0))
            for row_record in action_rows.values():
                row_record["hiddenByPolicy"] = True
        output_path = output_dir / f"{draft['visualAssetId']}_{action}.png"
        result = save_png(output, output_path)
        derived_paths[action] = to_res(root, output_path)
        source_sha[action] = sha256(evidence_path)
        derived_sha[action] = result["fileSha256"]
        action_metrics[action] = {
            "frameCount": frame_count,
            "evidencePath": evidence_path_value,
            "evidenceSha256": source_sha[action],
            "rows": action_rows,
        }
    return derived_paths, source_sha, derived_sha, action_metrics


def build_pose_authored_world_atlases(
    root: Path,
    draft: dict[str, Any],
    visual_asset: dict[str, Any],
    cutouts: dict[int, Image.Image],
    output_dir: Path,
) -> tuple[dict[str, str], dict[str, str], dict[str, str], dict[str, Any]]:
    placement_rows = {
        direction: int(draft["directions"][direction]["source_row"])
        for direction in DIRECTIONS
    }
    if set(placement_rows.values()) != set(range(8)):
        raise ValueError(
            "idle baseline must still map every runtime row exactly once"
        )
    direction_order = [
        str(value) for value in draft["source"]["directionOrder"]
    ]
    resized_cache: dict[tuple[int, int, int], Image.Image] = {}
    derived_paths: dict[str, str] = {}
    source_sha: dict[str, str] = {}
    derived_sha: dict[str, str] = {}
    action_metrics: dict[str, Any] = {}

    for action in ACTIONS:
        evidence_path_value = visual_asset["directions"]["N"]["layers"][
            "helmet_front"
        ][action]
        evidence_path = res_path(root, evidence_path_value)
        evidence = rgba(evidence_path)
        frame_count = evidence.width // FRAME_SIZE[0]
        if evidence.height != FRAME_SIZE[1] * 8 or frame_count <= 0:
            raise ValueError(f"invalid base atlas: {evidence_path}")
        output = Image.new("RGBA", evidence.size, (0, 0, 0, 0))
        action_rows: dict[str, Any] = {}

        for target_direction in DIRECTIONS:
            placement_row = placement_rows[target_direction]
            row_frames: list[dict[str, Any]] = []
            for frame in range(frame_count):
                pose = resolved_pose_transform(
                    draft, action, target_direction, frame
                )
                source_row = int(pose["source_row"])
                source_direction = direction_order[source_row]
                source_direction_record = visual_asset["directions"][
                    source_direction
                ]
                original = cutouts[source_row]
                target_size = (
                    max(
                        1,
                        int(
                            round(
                                original.width
                                * AUTHORED_WORLD_DISPLAY_SCALE
                                * int(pose["scale_x_percent"])
                                / 100.0
                            )
                        ),
                    ),
                    max(
                        1,
                        int(
                            round(
                                original.height
                                * AUTHORED_WORLD_DISPLAY_SCALE
                                * int(pose["scale_y_percent"])
                                / 100.0
                            )
                        ),
                    ),
                )
                pivot = pivot_for(
                    source_direction_record, action, frame
                )
                center = (
                    pivot[0] + float(pose["offset"][0]),
                    pivot[1] + float(pose["offset"][1]),
                )
                rotation = float(pose["rotation_degrees"])
                if math.isclose(rotation, 0.0):
                    cache_key = (
                        source_row, target_size[0], target_size[1]
                    )
                    if cache_key not in resized_cache:
                        resized_cache[cache_key] = (
                            premultiplied_lanczos_resize(
                                original, target_size
                            )
                        )
                    sprite = resized_cache[cache_key]
                    destination_cell = Image.new(
                        "RGBA", FRAME_SIZE, (0, 0, 0, 0)
                    )
                    left = int(round(center[0] - sprite.width / 2.0))
                    top = int(round(center[1] - sprite.height / 2.0))
                    destination_cell.alpha_composite(sprite, (left, top))
                    resample = "premultiplied_alpha_lanczos_original_single_pass"
                else:
                    destination_cell = premultiplied_affine_to_cell(
                        original, target_size, rotation, center
                    )
                    bbox = destination_cell.getchannel("A").getbbox()
                    if bbox is None:
                        raise ValueError(
                            "empty rotated pose: "
                            f"{action}/{target_direction}/{frame}"
                        )
                    left, top = bbox[0], bbox[1]
                    resample = (
                        "premultiplied_alpha_bicubic_affine_original_single_pass"
                    )
                output.alpha_composite(
                    destination_cell,
                    (
                        frame * FRAME_SIZE[0],
                        placement_row * FRAME_SIZE[1],
                    ),
                )
                row_frames.append(
                    {
                        "frame": frame,
                        "targetDirection": target_direction,
                        "runtimeRow": placement_row,
                        "sourceRow": source_row,
                        "sourceDirection": source_direction,
                        "size": list(target_size),
                        "pivot": [
                            round(pivot[0], 3),
                            round(pivot[1], 3),
                        ],
                        "center": [
                            round(center[0], 3),
                            round(center[1], 3),
                        ],
                        "topLeft": [left, top],
                        "offset": list(pose["offset"]),
                        "scaleXPercent": int(
                            pose["scale_x_percent"]
                        ),
                        "scaleYPercent": int(
                            pose["scale_y_percent"]
                        ),
                        "rotationDegrees": rotation,
                        "resample": resample,
                    }
                )
            action_rows[str(placement_row)] = {
                "targetDirection": target_direction,
                "poseFrameIndependentSource": True,
                "frames": row_frames,
            }

        if action in HIDDEN_HELMET_ACTIONS:
            output = Image.new("RGBA", evidence.size, (0, 0, 0, 0))
            for row_record in action_rows.values():
                row_record["hiddenByPolicy"] = True
                for frame_record in row_record["frames"]:
                    frame_record["hiddenByPolicy"] = True
        output_path = output_dir / f"{draft['visualAssetId']}_{action}.png"
        result = save_png(output, output_path)
        derived_paths[action] = to_res(root, output_path)
        source_sha[action] = sha256(evidence_path)
        derived_sha[action] = result["fileSha256"]
        action_metrics[action] = {
            "frameCount": frame_count,
            "evidencePath": evidence_path_value,
            "evidenceSha256": source_sha[action],
            "poseFrameIndependentSource": True,
            "rows": action_rows,
        }
    return derived_paths, source_sha, derived_sha, action_metrics


def replace_presentation_records(
    root: Path,
    draft: dict[str, Any],
    cutouts: dict[int, Image.Image],
    output_dir: Path,
    visual_catalog: dict[str, Any],
    head_manifest: dict[str, Any],
    item_ids: list[int],
) -> dict[str, Any]:
    primary_item_id = int(draft["itemId"])
    paper = draft["presentationCalibration"]["paperDoll"]
    paper_source, paper_provenance = presentation_source(
        root, draft, cutouts, "paperDoll"
    )
    reference_size = PAPER_REFERENCE_SIZES[primary_item_id]
    target_height = max(
        1,
        int(round(float(reference_size[1]) * int(paper["scale_percent"]) / 100.0)),
    )
    target_width = max(
        1, int(round(target_height * paper_source.width / paper_source.height))
    )
    paper_image = premultiplied_lanczos_resize(
        paper_source, (target_width, target_height)
    )
    draw_offset = paper_draw_offset(paper)
    paper_image = transparent_safe_border(paper_image)
    draw_offset = [
        round(draw_offset[0] - 1.0, 3),
        round(draw_offset[1] - 1.0, 3),
    ]

    inventory_source, inventory_provenance = presentation_source(
        root, draft, cutouts, "inventory"
    )
    inventory_image = premultiplied_lanczos_resize(
        inventory_source, fit_inside(inventory_source, (36, 36))
    )
    ground_source, ground_provenance = presentation_source(
        root, draft, cutouts, "ground"
    )
    ground_image = premultiplied_lanczos_resize(
        ground_source, fit_inside(ground_source, (18, 18))
    )

    records: dict[str, Any] = {}
    for item_id in item_ids:
        item_key = str(item_id)
        item = visual_catalog["itemsById"][item_key]
        item_name = str(item["itemName"])
        suffix = f"item_{item_id:05d}"
        paper_result = save_png(
            paper_image, output_dir / f"{suffix}_paper_doll.png"
        )
        erase_mask = Image.new("RGBA", paper_image.size, (255, 255, 255, 0))
        erase_alpha = paper_image.getchannel("A")
        erase_mask.putalpha(erase_alpha)
        erase_result = save_png(
            erase_mask, output_dir / f"{suffix}_erase_mask.png"
        )
        inventory_result = save_png(
            inventory_image, output_dir / f"{suffix}_inventory.png"
        )
        ground_result = save_png(
            ground_image, output_dir / f"{suffix}_ground.png"
        )

        paper_record = {
            "contractId": "equipment.paper_doll.classic_flattened_head_patch.v1",
            "itemId": item_id,
            "itemName": item_name,
            "slot": "头盔",
            "source": "user_final_helmet_calibration",
            "sourceIndex": item_id,
            "sourceRecordPath": str(
                paper_provenance.get(
                    "path", draft["source"]["sheet"]
                )
            ),
            "sourceDirection": str(paper["source_direction"]),
            "path": to_res(root, paper_result["path"]),
            "eraseMaskPath": to_res(root, erase_result["path"]),
            "drawOffset": draw_offset,
            "size": paper_result["size"],
            "fileSha256": paper_result["fileSha256"],
            "rgbaSha256": paper_result["rgbaSha256"],
            "eraseMaskFileSha256": erase_result["fileSha256"],
            "eraseMaskRgbaSha256": erase_result["rgbaSha256"],
            "drawOrder": ["male_head_anatomy", "male_hair", "helmet"],
            "calibrationDraftItemId": primary_item_id,
            "calibrationDraftSha256": sha256(
                root
                / "assets"
                / "data"
                / "helmet_calibration_drafts"
                / f"item_{primary_item_id}.json"
            ),
            "singlePassDownsample": True,
            "sourceAspectPreserved": True,
            "facePixelsBaked": False,
            "hairPixelsBaked": False,
            "subjectEvidence": {
                "method": "user_final_calibration_original_rgba_single_pass_v1",
                **paper_provenance,
                "scalePercent": int(paper["scale_percent"]),
                "calibrationOffset": list(paper["offset"]),
                "paperPreviewScale": PAPER_PREVIEW_SCALE,
                "paperCompositionOrigin": list(PAPER_COMPOSITION_ORIGIN),
                "paperReferenceSize": list(reference_size),
            },
            "headOnlyEvidence": {
                "bottomLeftAlpha": paper_image.getpixel(
                    (0, paper_image.height - 1)
                )[3],
                "bottomRightAlpha": paper_image.getpixel(
                    (paper_image.width - 1, paper_image.height - 1)
                )[3],
            },
        }
        head_manifest["itemsById"][item_key]["flattenedHeadPatch"] = paper_record
        head_manifest["runtimeMappings"][item_name] = paper_record

        paper_catalog = {
            "status": "user_final_helmet_calibration",
            "slot": "头盔",
            "gender": "通用",
            "sourceIndex": item_id,
            "path": paper_record["path"],
            "drawOffset": draw_offset,
            "rawDrawOffset": draw_offset,
            "size": paper_result["size"],
            "source": "user_final_helmet_calibration",
            "mappingConfidence": "user_approved_exact",
            "fileSha256": paper_result["fileSha256"],
            "rgbaSha256": paper_result["rgbaSha256"],
        }
        inventory_record = {
            "path": to_res(root, inventory_result["path"]),
            "library": "project.user_final_helmet_calibration",
            "index": item_id,
            "size": inventory_result["size"],
            "drawOffset": [0, 0],
            "confidence": "user_approved_exact",
            "sourceDirection": str(
                draft["presentationCalibration"]["inventory"]["source_direction"]
            ),
            "sourceVariant": str(
                draft["presentationCalibration"]["inventory"].get(
                    "source_variant", "direction"
                )
            ),
            "fileSha256": inventory_result["fileSha256"],
            "rgbaSha256": inventory_result["rgbaSha256"],
        }
        ground_record = {
            "path": to_res(root, ground_result["path"]),
            "library": "project.user_final_helmet_calibration",
            "index": item_id,
            "size": ground_result["size"],
            "drawOffset": [0, 0],
            "confidence": "user_approved_exact",
            "sourceDirection": str(
                draft["presentationCalibration"]["ground"]["source_direction"]
            ),
            "sourceVariant": str(
                draft["presentationCalibration"]["ground"].get(
                    "source_variant", "direction"
                )
            ),
            "fileSha256": ground_result["fileSha256"],
            "rgbaSha256": ground_result["rgbaSha256"],
        }
        item["paperDoll"] = paper_catalog
        item["icons"]["equippedSlot"] = {
            **paper_catalog,
            "confidence": "user_approved_exact",
        }
        item["icons"]["inventory"] = inventory_record
        item["icons"]["ground"] = ground_record
        # Name-only legacy saves still resolve world appearance through this
        # compatibility map. Presentation calibration belongs on the item
        # record and must never replace its helmetAppearance mapping.
        visual_catalog["runtimeMappings"][item_name] = {
            "helmetAppearance": item["worldWear"]["helmetAppearance"]
        }
        records[item_key] = {
            "paperDoll": paper_record,
            "inventory": {**inventory_record, "provenance": inventory_provenance},
            "ground": {**ground_record, "provenance": ground_provenance},
        }
    return records


def normalized_direction_record(record: dict[str, Any]) -> dict[str, Any]:
    return {
        "source_row": int(record["source_row"]),
        "source_slot_id": str(record["source_slot_id"]),
        "nudge": [float(record["nudge"][0]), float(record["nudge"][1])],
        "scale_percent": int(record["scale_percent"]),
        "status": str(record["status"]),
        "locked": bool(record["locked"]),
        "source_direction": str(record["source_direction"]),
    }


def finalize(root: Path) -> dict[str, Any]:
    drafts_dir = root / "assets/data/helmet_calibration_drafts"
    catalog_path = root / "assets/data/equipment_helmet_visual_v2.json"
    override_path = root / "assets/data/equipment_helmet_visual_v2_overrides.json"
    visual_catalog_path = root / "assets/data/equipment_visual_catalog.json"
    head_manifest_path = root / "assets/data/equipment_classic_avatar_head_patches.json"
    final_manifest_path = root / "assets/data/equipment_helmet_finalization_manifest.json"

    helmet_catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    overrides = json.loads(override_path.read_text(encoding="utf-8"))
    visual_catalog = json.loads(visual_catalog_path.read_text(encoding="utf-8"))
    head_manifest = json.loads(head_manifest_path.read_text(encoding="utf-8"))

    draft_paths = sorted(
        drafts_dir.glob("item_*.json"),
        key=lambda value: int(value.stem.removeprefix("item_")),
    )
    if [int(path.stem.removeprefix("item_")) for path in draft_paths] != [
        146,
        147,
        149,
        150,
        151,
        218,
        224,
        228,
        232,
        236,
        240,
    ]:
        raise ValueError("unexpected final calibration draft set")

    manifest: dict[str, Any] = {
        "schemaVersion": 1,
        "contractId": "equipment.helmet.finalization.v1",
        "runtimeReadable": True,
        "sourcePolicy": {
            "lane": "user_authorized_direct_source",
            "primary": "immutable_final_calibration_drafts",
            "baseAtlasesUsedForPixels": False,
            "baseAtlasesUsedForMotionEvidenceOnly": True,
            "singlePassDownsample": "premultiplied_alpha_lanczos_from_original",
            "runtimeTextureFilter": "nearest",
            "runtimeScale": [1, 1],
            "hiddenHelmetActions": sorted(HIDDEN_HELMET_ACTIONS),
        },
        "paperCalibrationLayout": {
            "canvasSize": list(PAPER_CALIBRATION_CANVAS),
            "previewScale": PAPER_PREVIEW_SCALE,
            "compositionOrigin": list(PAPER_COMPOSITION_ORIGIN),
        },
        "items": {},
    }

    for draft_path in draft_paths:
        draft_bytes_before = draft_path.read_bytes()
        draft = json.loads(draft_bytes_before)
        item_id = int(draft["itemId"])
        asset_id = str(draft["visualAssetId"])
        pose_source_enabled = bool(
            draft.get("previewPolicy", {}).get(
                "poseFrameIndependentSource", False
            )
        )
        visual_asset = helmet_catalog["visualAssets"][asset_id]
        item_ids = [int(value) for value in visual_asset.get("itemIds", [item_id])]
        if item_id not in item_ids:
            item_ids.insert(0, item_id)
        cutouts, source_provenance = source_cutouts(root, draft)
        profile_id = hashlib.sha256(draft_bytes_before).hexdigest()[:12]
        output_dir = (
            root
            / "assets/generated/helmet_v2"
            / asset_id
            / f"final_{profile_id}"
        )
        presentation_dir = (
            root
            / "assets/generated/helmet_presentation"
            / asset_id
            / f"final_{profile_id}"
        )
        (
            derived_paths,
            source_sha,
            derived_sha,
            action_metrics,
        ) = build_world_atlases(
            root, draft, visual_asset, cutouts, output_dir
        )
        presentation_records = replace_presentation_records(
            root,
            draft,
            cutouts,
            presentation_dir,
            visual_catalog,
            head_manifest,
            item_ids,
        )

        item_override = overrides["itemOverrides"].setdefault(str(item_id), {})
        item_override["directions"] = {
            direction: normalized_direction_record(draft["directions"][direction])
            for direction in DIRECTIONS
        }
        scale_profile = {
            direction: int(draft["directions"][direction]["scale_percent"])
            for direction in DIRECTIONS
        }
        unique_scales = set(scale_profile.values())
        asset_override = overrides["visualAssetOverrides"].setdefault(asset_id, {})
        asset_override.update(
            {
                "uniform_scale_percent": (
                    next(iter(unique_scales)) if len(unique_scales) == 1 else 100
                ),
                "directionScalePercent": scale_profile,
                "derivedAtlases": derived_paths,
                "sourceAtlasSha256": source_sha,
                "derivedAtlasSha256": derived_sha,
                "presentationCalibration": draft["presentationCalibration"],
                "bakePolicy": {
                    "filter": "premultiplied_alpha_lanczos_original_single_pass",
                    "sourceAspectPreserved": True,
                    "idleSizing": "area_equivalent_aspect_preserving",
                    "motionTransform": (
                        "head_pivot_translation_plus_bounded_second_moment_xy"
                    ),
                    "normalActionAspectLogLimit": NORMAL_ASPECT_LIMIT,
                    "deathActionAspectLogLimit": DEATH_ASPECT_LIMIT,
                    "pivotInvariant": True,
                    "directionIndependent": True,
                    "allActionsDirectionsFrames": True,
                    "requiredActions": list(ACTIONS),
                    "runtimeScale": [1, 1],
                    "runtimeTextureFilter": "nearest",
                    "sourceAtlasModified": False,
                    "hiddenHelmetActions": sorted(HIDDEN_HELMET_ACTIONS),
                    "sourceRecipeId": (
                        f"final_calibration.{asset_id}.{profile_id}."
                        "original_rgba_single_pass_v1"
                    ),
                    "draftPath": to_res(root, draft_path),
                    "draftSha256": hashlib.sha256(draft_bytes_before).hexdigest(),
                },
            }
        )
        if pose_source_enabled:
            asset_override["poseTransforms"] = draft.get(
                "poseTransforms", {}
            )
            asset_override["bakePolicy"].update(
                {
                    "poseFrameIndependentSource": True,
                    "poseFrameIndependentOffset": True,
                    "poseFrameIndependentAxisScale": True,
                    "poseFrameIndependentRotation": True,
                    "nonRotatedResample": (
                        "premultiplied_alpha_lanczos_original_single_pass"
                    ),
                    "rotatedResample": (
                        "premultiplied_alpha_bicubic_affine_original_single_pass"
                    ),
                }
            )
        manifest["items"][str(item_id)] = {
            "itemId": item_id,
            "sharedItemIds": item_ids,
            "visualAssetId": asset_id,
            "draftPath": to_res(root, draft_path),
            "draftSha256": hashlib.sha256(draft_bytes_before).hexdigest(),
            "sourceSheet": draft["source"]["sheet"],
            "sourceSheetSha256": draft["source"]["sheetSha256"],
            "sourceDirections": source_provenance,
            "directionCalibration": draft["directions"],
            "presentationCalibration": draft["presentationCalibration"],
            "runtimeAtlases": derived_paths,
            "runtimeAtlasSha256": derived_sha,
            "motionEvidenceAtlasSha256": source_sha,
            "actionMetrics": action_metrics,
            "presentationOutputs": presentation_records,
        }
        if pose_source_enabled:
            manifest["items"][str(item_id)]["poseTransforms"] = (
                draft.get("poseTransforms", {})
            )
            manifest["items"][str(item_id)]["worldBakePolicy"] = {
                "poseFrameIndependentSource": True,
                "runtimeRowIndependentFromSelectedSourceRow": True,
                "sharedSourceRowsAllowed": True,
                "perTargetPoseBakedIndependently": True,
            }
        if draft_path.read_bytes() != draft_bytes_before:
            raise RuntimeError(f"frozen calibration draft changed: {draft_path}")

    write_json(override_path, overrides)
    write_json(visual_catalog_path, visual_catalog)
    write_json(head_manifest_path, head_manifest)
    write_json(final_manifest_path, manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--project-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    args = parser.parse_args()
    root = args.project_root.resolve()
    manifest = finalize(root)
    print(
        "FINALIZED_HELMETS="
        + ",".join(str(value["itemId"]) for value in manifest["items"].values())
    )
    print(
        "FINALIZATION_MANIFEST_SHA256="
        + sha256(root / "assets/data/equipment_helmet_finalization_manifest.json")
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
