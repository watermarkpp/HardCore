#!/usr/bin/env python3
"""Build and validate the male-only generated world-helmet extension.

StateItem records are identity evidence only. Runtime pixels come exclusively
from approved eight-direction concept sheets. Every generated cell follows the
matching male Hair.wil action/direction/frame head anchor, stays inside the
accepted 192x160 actor cell and records source and rendered RGBA hashes.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from collections import deque
from copy import deepcopy
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RECIPES = ROOT / "assets/data/equipment_male_world_helmet_recipes.json"
CONTRACT = ROOT / "assets/data/equipment_male_world_helmet.json"
VISUAL_CATALOG = ROOT / "assets/data/equipment_visual_catalog.json"
CLIENT_BASELINE = (
    ROOT
    / "outputs/resource_catalog/black_iron_helmet"
    / "client_helmet_parameter_baseline.json"
)
HAIR_SOURCE = (
    ROOT
    / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"
)
BLACK_IRON_SOURCE = (
    ROOT
    / "assets/art/characters/warrior/wear/helmet"
    / "black_iron_helmet.source.json"
)

CONTRACT_ID = "equipment.world_helmet.male.extension.v1"
DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
CELL = (192, 160)
FOOT_ANCHOR = (64, 80)
HAIR_APPEARANCE = 2
HAIR_STRIDE = 2224
VISUAL_MASS_TARGET_MULTIPLIER = 1.15
ACTION_SPECS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}
EXPECTED_ITEM_IDS = {
    146,
    147,
    148,
    149,
    150,
    151,
    218,
    224,
    228,
    232,
    236,
    240,
}
BLACK_IRON_PRESERVED_ACTIONS = {
    "idle",
    "walk",
    "attack",
    "hit",
    "death",
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def rgba_sha256(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def resource_path(path: Path) -> str:
    return f"res://{path.relative_to(ROOT).as_posix()}"


def disk_path(value: str) -> Path:
    if not value.startswith("res://"):
        raise ValueError(f"resource path must start with res://: {value}")
    return ROOT / value.removeprefix("res://")


def effective_opaque_pixels(image: Image.Image) -> float:
    histogram = image.getchannel("A").histogram()
    return sum(alpha * count for alpha, count in enumerate(histogram)) / 255.0


def alpha_centroid(image: Image.Image) -> tuple[float, float]:
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        raise ValueError("cannot measure an empty image")
    weighted_x = 0.0
    weighted_y = 0.0
    total = 0.0
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            weight = alpha.getpixel((x, y)) / 255.0
            if weight <= 0.0:
                continue
            weighted_x += x * weight
            weighted_y += y * weight
            total += weight
    return weighted_x / total, weighted_y / total


def median_rgb(values: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    if not values:
        raise ValueError("cannot find a matte colour from an empty border")
    ordered = [sorted(pixel[channel] for pixel in values) for channel in range(3)]
    middle = len(values) // 2
    return tuple(channel[middle] for channel in ordered)


def largest_component(mask: Image.Image) -> Image.Image:
    """Keep the principal connected helmet and discard labels or stray marks."""
    width, height = mask.size
    source = mask.tobytes()
    visited = bytearray(width * height)
    largest: list[int] = []
    for seed, value in enumerate(source):
        if value == 0 or visited[seed]:
            continue
        visited[seed] = 1
        queue: deque[int] = deque([seed])
        component: list[int] = []
        while queue:
            index = queue.popleft()
            component.append(index)
            x = index % width
            y = index // width
            for nx, ny in (
                (x - 1, y),
                (x + 1, y),
                (x, y - 1),
                (x, y + 1),
                (x - 1, y - 1),
                (x + 1, y - 1),
                (x - 1, y + 1),
                (x + 1, y + 1),
            ):
                if nx < 0 or nx >= width or ny < 0 or ny >= height:
                    continue
                neighbour = ny * width + nx
                if source[neighbour] and not visited[neighbour]:
                    visited[neighbour] = 1
                    queue.append(neighbour)
        if len(component) > len(largest):
            largest = component
    if not largest:
        raise ValueError("concept slot is empty after matte removal")
    result = bytearray(width * height)
    for index in largest:
        result[index] = 255
    return Image.frombytes("L", (width, height), bytes(result))


def remove_matte(slot: Image.Image, tolerance: int) -> Image.Image:
    """Remove a locally sampled background without accepting StateItem pixels."""
    rgba = slot.convert("RGBA")
    alpha = rgba.getchannel("A")
    soft_alpha: Image.Image
    if alpha.getextrema()[0] < 255:
        mask = alpha.point(lambda value: 255 if value >= 8 else 0)
        soft_alpha = alpha
    else:
        rgb = rgba.convert("RGB")
        width, height = rgb.size
        edge_width = min(10, max(2, width // 24))
        left_by_row: list[tuple[int, int, int]] = []
        right_by_row: list[tuple[int, int, int]] = []
        for y in range(height):
            left_by_row.append(
                median_rgb(
                    [rgb.getpixel((x, y)) for x in range(edge_width)]
                )
            )
            right_by_row.append(
                median_rgb(
                    [
                        rgb.getpixel((width - 1 - x, y))
                        for x in range(edge_width)
                    ]
                )
            )
        mask = Image.new("L", rgb.size, 0)
        soft_alpha = Image.new("L", rgb.size, 0)
        pixels = mask.load()
        soft_pixels = soft_alpha.load()
        source = rgb.load()
        denominator = max(1, width - 1)
        for y in range(height):
            left = left_by_row[y]
            right = right_by_row[y]
            for x in range(width):
                fraction = x / denominator
                expected = tuple(
                    round(left[channel] * (1.0 - fraction) + right[channel] * fraction)
                    for channel in range(3)
                )
                difference = max(
                    abs(source[x, y][channel] - expected[channel])
                    for channel in range(3)
                )
                if difference > tolerance:
                    pixels[x, y] = 255
                    soft_pixels[x, y] = min(
                        255,
                        round(
                            (difference - tolerance)
                            * 255
                            / max(24, tolerance * 3)
                        ),
                    )
    principal = largest_component(mask)
    box = principal.getbbox()
    if box is None:
        raise ValueError("concept slot has no retained helmet component")
    principal_crop = principal.crop(box)
    soft_crop = soft_alpha.crop(box)
    final_alpha = Image.new("L", principal_crop.size, 0)
    final_alpha.putdata(
        [
            min(component, softness)
            for component, softness in zip(
                principal_crop.tobytes(),
                soft_crop.tobytes(),
            )
        ]
    )
    crop = rgba.crop(box)
    # Green-screen concepts need edge decontamination in addition to alpha
    # removal. Limit it to the two-pixel component boundary so legitimate
    # green helmet plates and gems remain untouched.
    interior = principal_crop.filter(ImageFilter.MinFilter(5))
    colour_pixels = crop.load()
    interior_pixels = interior.load()
    alpha_pixels = final_alpha.load()
    for y in range(crop.height):
        for x in range(crop.width):
            if alpha_pixels[x, y] == 0:
                continue
            red, green, blue, _opacity = colour_pixels[x, y]
            if green >= 245 and red <= 12 and blue <= 12:
                alpha_pixels[x, y] = 0
                continue
            if interior_pixels[x, y] == 255:
                continue
            strongest_non_green = max(red, blue)
            if green >= 140 and green - strongest_non_green >= 40:
                colour_pixels[x, y] = (
                    red,
                    strongest_non_green,
                    blue,
                    255,
                )
    crop.putalpha(final_alpha)
    # Zero RGB under full transparency so LANCZOS downscaling cannot bleed
    # chroma-key green back into a visible edge or enclosed helmet opening.
    colour_pixels = crop.load()
    for y in range(crop.height):
        for x in range(crop.width):
            if colour_pixels[x, y][3] == 0:
                colour_pixels[x, y] = (0, 0, 0, 0)
    if crop.getchannel("A").getbbox() is None:
        raise ValueError("concept cutout is empty")
    return crop


def validated_direction_mapping(recipe: dict) -> tuple[list[int], list[str]]:
    identity_id = str(recipe.get("identityId", "unknown"))
    grid = recipe.get("sourceGrid", [])
    if (
        not isinstance(grid, list)
        or len(grid) != 2
        or int(grid[0]) * int(grid[1]) != 8
    ):
        raise ValueError(f"{identity_id} must declare an eight-slot sourceGrid")
    if recipe.get("directionClassificationStatus") != (
        "accepted_manual_visual_classification"
    ):
        raise ValueError(
            f"{identity_id} direction mapping is BLOCKED: every source slot "
            "must be visually classified from face opening, nose/ornament "
            "projection, rear shell and left/right edge before generation"
        )
    evidence = str(recipe.get("directionClassificationEvidence", "")).strip()
    if not evidence:
        raise ValueError(
            f"{identity_id} lacks manual direction-classification evidence"
        )
    slot_order = list(recipe.get("sourceSlotDirectionOrder", []))
    if len(slot_order) != 8 or sorted(slot_order) != sorted(DIRECTIONS):
        raise ValueError(
            f"{identity_id} direction mapping is BLOCKED: source slots "
            "contain a duplicate or missing canonical direction"
        )
    canonical_slots = [
        int(value) for value in recipe.get("canonicalRowSourceSlots", [])
    ]
    expected_slots = [slot_order.index(direction) for direction in DIRECTIONS]
    if canonical_slots != expected_slots:
        raise ValueError(
            f"{identity_id} canonicalRowSourceSlots does not match its "
            "independently classified source slots"
        )
    if sorted(canonical_slots) != list(range(8)):
        raise ValueError(
            f"{identity_id} canonical row mapping is not one-to-one"
        )
    return canonical_slots, slot_order


def source_slot_crop(
    concept: Image.Image,
    grid: list[int],
    source_slot: int,
) -> Image.Image:
    columns, rows = map(int, grid)
    column = source_slot % columns
    row = source_slot // columns
    left = round(column * concept.width / columns)
    right = round((column + 1) * concept.width / columns)
    top = round(row * concept.height / rows)
    bottom = round((row + 1) * concept.height / rows)
    return concept.crop((left, top, right, bottom))


def concept_cutouts(recipe: dict) -> dict[str, Image.Image]:
    path = disk_path(str(recipe["concept"]))
    concept = Image.open(path).convert("RGBA")
    if concept.width < 8 or concept.height < 8:
        raise ValueError(f"concept sheet is too small: {path}")
    _canonical_slots, slot_order = validated_direction_mapping(recipe)
    grid = list(recipe["sourceGrid"])
    tolerance = int(recipe.get("matteTolerance", 12))
    by_direction: dict[str, Image.Image] = {}
    for source_slot, direction in enumerate(slot_order):
        cutout = remove_matte(
            source_slot_crop(concept, grid, source_slot),
            tolerance,
        )
        if bool(recipe.get("despillGreenCutouts", False)):
            cutout = despill_green_matte(cutout)
        by_direction[direction] = cutout
    signatures = {rgba_sha256(by_direction[value]) for value in DIRECTIONS}
    if len(signatures) < 6:
        raise AssertionError(
            f"{recipe['identityId']} concept does not contain a usable "
            "eight-direction visual family"
        )
    return by_direction


def approved_calibration_cutouts(
    recipe: dict,
) -> dict[str, Image.Image] | None:
    """Build the user-approved transparent sheet without dropping components.

    The calibration sheet is deliberately derived from the complete authored
    source cell. Unlike ``remove_matte``, it does not select only the largest
    connected component, so detached trim, cheek guards and edge ornaments
    remain available to both the source buttons and the worn-world bake.
    """
    target_value = str(recipe.get("calibrationSourceSheet", "")).strip()
    if not target_value:
        return None
    matte_policy = str(recipe.get("calibrationSourceMatte", ""))
    if matte_policy not in {
        "transparent_user_approved_despill_v1",
        "transparent_user_authorized_redesign_despill_v1",
    }:
        raise ValueError(
            f"{recipe['identityId']} has unsupported calibration matte "
            f"policy: {matte_policy}"
        )
    concept = Image.open(disk_path(str(recipe["concept"]))).convert("RGBA")
    transparent = despill_green_matte(concept)
    target = disk_path(target_value)
    save_deterministic_atlas(target, transparent)

    _canonical_slots, slot_order = validated_direction_mapping(recipe)
    grid = list(recipe["sourceGrid"])
    by_direction: dict[str, Image.Image] = {}
    for source_slot, direction in enumerate(slot_order):
        cell = source_slot_crop(transparent, grid, source_slot)
        box = cell.getchannel("A").getbbox()
        if box is None:
            raise ValueError(
                f"{recipe['identityId']} calibration source slot "
                f"{source_slot} is empty"
            )
        by_direction[direction] = cell.crop(box)
    return by_direction


def calibration_source_metadata(recipe: dict) -> dict:
    target_value = str(recipe.get("calibrationSourceSheet", "")).strip()
    if not target_value:
        return {}
    target = disk_path(target_value)
    if not target.exists():
        raise FileNotFoundError(
            f"missing built calibration source sheet: {target}"
        )
    return {
        "calibrationSourceSheet": target_value,
        "calibrationSourceSheetSha256": file_sha256(target),
        "calibrationSourceGrid": list(recipe["sourceGrid"]),
        "calibrationSourceSlotDirectionOrder": list(
            recipe["sourceSlotDirectionOrder"]
        ),
        "calibrationPreparedSourceRows": [],
        "calibrationSourceMatte": str(
            recipe["calibrationSourceMatte"]
        ),
        "calibrationResizeFilter": str(
            recipe["calibrationResizeFilter"]
        ),
    }


def build_direction_acceptance_sheet(
    recipe: dict,
    cutouts: dict[str, Image.Image],
) -> dict:
    canonical_slots, slot_order = validated_direction_mapping(recipe)
    tile_width = 128
    canvas = Image.new(
        "RGBA",
        (tile_width * 8, 176),
        (15, 17, 21, 255),
    )
    draw = ImageDraw.Draw(canvas)
    draw.text(
        (8, 7),
        f"{recipe['identityId']} manual source-slot classification",
        fill=(238, 238, 238, 255),
    )
    for source_slot, direction in enumerate(slot_order):
        cutout = cutouts[direction]
        scale = min(96 / cutout.width, 96 / cutout.height)
        size = (
            max(1, round(cutout.width * scale)),
            max(1, round(cutout.height * scale)),
        )
        preview = cutout.resize(size, Image.Resampling.NEAREST)
        x = source_slot * tile_width + (tile_width - preview.width) // 2
        y = 31 + (100 - preview.height) // 2
        canvas.alpha_composite(preview, (x, y))
        draw.text(
            (source_slot * tile_width + 7, 134),
            f"S{source_slot} -> {direction}",
            fill=(255, 214, 87, 255),
        )
    draw.text(
        (8, 157),
        "canonical rows: "
        + " ".join(
            f"{direction}:S{canonical_slots[row]}"
            for row, direction in enumerate(DIRECTIONS)
        ),
        fill=(183, 211, 255, 255),
    )
    target = (
        ROOT
        / "assets/art/items/client/world_wear/helmet/male/acceptance"
        / f"{recipe['identityId']}_direction_mapping.png"
    )
    save_deterministic_atlas(target, canvas)
    return {
        "path": resource_path(target),
        "fileSha256": file_sha256(target),
        "sourceGrid": list(recipe["sourceGrid"]),
        "sourceSlotDirectionOrder": slot_order,
        "canonicalRowSourceSlots": canonical_slots,
        "classificationStatus": str(
            recipe["directionClassificationStatus"]
        ),
        "classificationEvidence": str(
            recipe["directionClassificationEvidence"]
        ),
    }


def fit_to_client_envelope_with_scale(
    cutout: Image.Image,
    maximum_size: list[int],
    target_opaque_pixels: float,
) -> tuple[Image.Image, float]:
    maximum_width, maximum_height = map(int, maximum_size)
    maximum_scale = min(
        maximum_width / cutout.width,
        maximum_height / cutout.height,
    )
    if maximum_scale <= 0.0:
        raise ValueError("invalid client helmet envelope")
    target_mass = target_opaque_pixels * VISUAL_MASS_TARGET_MULTIPLIER
    candidates: dict[tuple[int, int], tuple[Image.Image, float]] = {}
    for step in range(1, 501):
        scale = maximum_scale * step / 500.0
        size = (
            max(1, round(cutout.width * scale)),
            max(1, round(cutout.height * scale)),
        )
        if size not in candidates:
            candidates[size] = (
                cutout.resize(size, Image.Resampling.LANCZOS),
                scale,
            )
    result, selected_scale = min(
        candidates.values(),
        key=lambda candidate: (
            abs(
                math.log(
                    max(effective_opaque_pixels(candidate[0]), 0.001)
                    / target_mass
                )
            ),
            -effective_opaque_pixels(candidate[0]),
        ),
    )
    if result.width > maximum_width or result.height > maximum_height:
        raise AssertionError("resized concept exceeds client median envelope")
    result = result.copy()
    result_pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, opacity = result_pixels[x, y]
            if opacity <= 7:
                result_pixels[x, y] = (0, 0, 0, 0)
    return result, selected_scale


def fit_to_client_envelope(
    cutout: Image.Image,
    maximum_size: list[int],
    target_opaque_pixels: float,
) -> Image.Image:
    result, _selected_scale = fit_to_client_envelope_with_scale(
        cutout,
        maximum_size,
        target_opaque_pixels,
    )
    return result


def helmet_body_box(
    cutout: Image.Image,
    policy: dict,
) -> tuple[int, int, int, int]:
    """Find the dense main helmet body while excluding long lateral horns."""
    if str(policy.get("method", "")) != "central_column_density":
        raise ValueError(
            "bodyDrivenSizing.method must be central_column_density"
        )
    threshold_percent = float(policy["columnDensityThresholdPercent"])
    maximum_gap_percent = float(policy["maximumColumnGapPercent"])
    padding_percent = float(policy["horizontalPaddingPercent"])
    body_top_crop_percent = float(
        policy.get("bodyTopCropPercent", 0.0)
    )
    if not (5.0 <= threshold_percent <= 90.0):
        raise ValueError(
            "columnDensityThresholdPercent must be between 5 and 90"
        )
    if not (0.0 <= maximum_gap_percent <= 25.0):
        raise ValueError(
            "maximumColumnGapPercent must be between 0 and 25"
        )
    if not (0.0 <= padding_percent <= 20.0):
        raise ValueError(
            "horizontalPaddingPercent must be between 0 and 20"
        )
    if not (0.0 <= body_top_crop_percent <= 50.0):
        raise ValueError(
            "bodyTopCropPercent must be between 0 and 50"
        )

    alpha = cutout.getchannel("A")
    body_top = round(cutout.height * body_top_crop_percent / 100.0)
    column_mass = [
        sum(
            alpha.getpixel((x, y))
            for y in range(body_top, cutout.height)
        )
        / 255.0
        for x in range(cutout.width)
    ]
    peak_mass = max(column_mass, default=0.0)
    if peak_mass <= 0.0:
        raise ValueError("cannot measure the body of an empty helmet")
    peak_x = max(range(cutout.width), key=column_mass.__getitem__)
    threshold = peak_mass * threshold_percent / 100.0
    active_columns = [
        x for x, mass in enumerate(column_mass) if mass >= threshold
    ]
    if not active_columns:
        raise ValueError("helmet body density threshold removed every column")

    maximum_gap = max(
        1,
        round(cutout.width * maximum_gap_percent / 100.0),
    )
    groups: list[tuple[int, int]] = []
    start = active_columns[0]
    previous = start
    for x in active_columns[1:]:
        if x - previous > maximum_gap:
            groups.append((start, previous))
            start = x
        previous = x
    groups.append((start, previous))
    body_group = next(
        (
            group
            for group in groups
            if group[0] <= peak_x <= group[1]
        ),
        max(groups, key=lambda group: group[1] - group[0]),
    )
    padding = max(1, round(cutout.width * padding_percent / 100.0))
    left = max(0, body_group[0] - padding)
    right = min(cutout.width, body_group[1] + 1 + padding)
    body_alpha_box = alpha.crop(
        (left, body_top, right, cutout.height)
    ).getbbox()
    if body_alpha_box is None:
        raise ValueError("helmet body box is empty")
    box = (
        left,
        body_top + int(body_alpha_box[1]),
        right,
        body_top + int(body_alpha_box[3]),
    )
    width_fraction = (box[2] - box[0]) / cutout.width
    minimum_fraction = float(policy["minimumBodyWidthFraction"])
    maximum_fraction = float(policy["maximumBodyWidthFraction"])
    if not minimum_fraction <= width_fraction <= maximum_fraction:
        raise AssertionError(
            "helmet body detection did not exclude the lateral horns: "
            f"{width_fraction:.4f} not in "
            f"[{minimum_fraction:.4f}, {maximum_fraction:.4f}]"
        )
    return box


def fit_body_to_client_envelope(
    cutout: Image.Image,
    maximum_size: list[int],
    target_opaque_pixels: float,
    policy: dict,
) -> tuple[Image.Image, dict]:
    """Scale the complete helmet from its horn-free main body measurement."""
    body_box = helmet_body_box(cutout, policy)
    body_reference = cutout.crop(body_box)
    fitted_body, candidate_scale = fit_to_client_envelope_with_scale(
        body_reference,
        maximum_size,
        target_opaque_pixels,
    )
    shared_target_height = int(
        policy.get("sharedBodyTargetHeightPixels", 0)
    )
    selected_scale = (
        shared_target_height / body_reference.height
        if shared_target_height > 0
        else candidate_scale
    )
    generated_body = body_reference.resize(
        (
            max(1, round(body_reference.width * selected_scale)),
            max(1, round(body_reference.height * selected_scale)),
        ),
        Image.Resampling.LANCZOS,
    )
    full_size = (
        max(1, round(cutout.width * selected_scale)),
        max(1, round(cutout.height * selected_scale)),
    )
    result = cutout.resize(full_size, Image.Resampling.LANCZOS)
    result = result.copy()
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, opacity = pixels[x, y]
            if opacity <= 7:
                pixels[x, y] = (0, 0, 0, 0)
    excluded_accessory = str(
        policy.get("excludedAccessory", "two_long_lateral_horns")
    )
    return result, {
        "enabled": True,
        "method": "central_column_density",
        "clientEnvelopeAppliedTo": "main_helmet_body_only",
        "excludedAccessory": excluded_accessory,
        "accessoryExcludedFromScaleCalculation": True,
        "hornsExcludedFromScaleCalculation": (
            excluded_accessory == "two_long_lateral_horns"
        ),
        "fullBoundsMayExceedClientEnvelope": True,
        "sourceBodyBox": list(body_box),
        "sourceBodySize": [
            body_reference.width,
            body_reference.height,
        ],
        "generatedBodySize": [
            generated_body.width,
            generated_body.height,
        ],
        "fullGeneratedSize": [result.width, result.height],
        "directionalCandidateBodySize": [
            fitted_body.width,
            fitted_body.height,
        ],
        "directionalCandidateScale": round(candidate_scale, 8),
        "selectedScale": round(selected_scale, 8),
        "sharedBodyTargetHeightPixels": shared_target_height,
        "uniformEditorScaleAcrossDirections": bool(
            policy.get("uniformEditorScaleAcrossDirections", False)
        ),
        "columnDensityThresholdPercent": float(
            policy["columnDensityThresholdPercent"]
        ),
        "maximumColumnGapPercent": float(
            policy["maximumColumnGapPercent"]
        ),
        "horizontalPaddingPercent": float(
            policy["horizontalPaddingPercent"]
        ),
        "bodyTopCropPercent": float(
            policy.get("bodyTopCropPercent", 0.0)
        ),
    }


def project_horizontal_diameter(
    image: Image.Image,
    direction: str,
    policy: dict,
) -> tuple[Image.Image, dict]:
    """Shrink the physical horizontal diameter without changing height.

    The lateral and front/back axes are projected at the direction yaw before
    resizing. Scaling both physical axes to 90% makes every view 90% as wide,
    including the side views, while each generated frame remains centred on
    its own direction-specific head pivot.
    """
    yaw_degrees = {
        "N": 180.0,
        "NE": 135.0,
        "E": 90.0,
        "SE": 45.0,
        "S": 0.0,
        "SW": -45.0,
        "W": -90.0,
        "NW": -135.0,
    }[direction]
    lateral_scale = float(policy["lateralDiameterPercent"]) / 100.0
    depth_scale = float(policy["depthDiameterPercent"]) / 100.0
    depth_to_width = float(policy.get("depthToWidthRatio", 1.0))
    if not (0.5 <= lateral_scale <= 2.0):
        raise ValueError(
            "lateralDiameterPercent must be between 50 and 200"
        )
    if not (0.5 <= depth_scale <= 2.0):
        raise ValueError(
            "depthDiameterPercent must be between 50 and 200"
        )
    if depth_to_width <= 0.0:
        raise ValueError("depthToWidthRatio must be positive")
    yaw = math.radians(yaw_degrees)
    lateral_projection = abs(math.cos(yaw))
    depth_projection = abs(math.sin(yaw)) * depth_to_width
    projected_before = lateral_projection + depth_projection
    projected_after = (
        lateral_projection * lateral_scale
        + depth_projection * depth_scale
    )
    projected_scale = projected_after / projected_before
    target_width = max(1, round(image.width * projected_scale))
    result = image.resize(
        (target_width, image.height),
        Image.Resampling.NEAREST,
    )
    return result, {
        "yawDegrees": yaw_degrees,
        "lateralDiameterPercent": round(lateral_scale * 100.0, 4),
        "depthDiameterPercent": round(depth_scale * 100.0, 4),
        "depthToWidthRatio": depth_to_width,
        "projectedHorizontalPercent": round(
            projected_scale * 100.0,
            4,
        ),
        "integerPixelHorizontalPercent": round(
            target_width / image.width * 100.0,
            4,
        ),
        "heightPercent": 100,
        "preProjectionSize": [image.width, image.height],
        "postProjectionSize": [result.width, result.height],
        "filter": "nearest",
        "pivotPolicy": "direction_frame_head_pivot_preserved",
    }


def despill_green_matte(image: Image.Image) -> Image.Image:
    result = image.copy()
    pixels = result.load()
    for y in range(result.height):
        for x in range(result.width):
            red, green, blue, opacity = pixels[x, y]
            non_green = max(red, blue)
            green_spill = max(0, green - non_green)
            if green_spill > 0:
                opacity = round(
                    opacity * max(0.0, 1.0 - green_spill / 114.75)
                )
                green = min(green, non_green + 6)
            if opacity <= 5:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (red, green, blue, opacity)
    return result


def build_variants(
    recipe: dict,
    baseline: dict,
) -> tuple[dict[str, Image.Image], dict[str, dict], dict]:
    cutouts = approved_calibration_cutouts(recipe)
    if cutouts is None:
        cutouts = concept_cutouts(recipe)
    acceptance = build_direction_acceptance_sheet(recipe, cutouts)
    canonical_slots = list(recipe["canonicalRowSourceSlots"])
    variants: dict[str, Image.Image] = {}
    records: dict[str, dict] = {}
    calibration_scale = int(recipe.get("calibrationBaseScalePercent", 100))
    if calibration_scale < 50 or calibration_scale > 200:
        raise ValueError(
            f"{recipe['identityId']} calibrationBaseScalePercent "
            f"must be between 50 and 200"
        )
    direction_scale_overrides = recipe.get(
        "directionScalePercentOverrides", {}
    )
    if not isinstance(direction_scale_overrides, dict):
        raise ValueError("directionScalePercentOverrides must be an object")
    diameter_policy = recipe.get("angleAwareHorizontalDiameter", {})
    if diameter_policy and not isinstance(diameter_policy, dict):
        raise ValueError("angleAwareHorizontalDiameter must be an object")
    body_sizing_policy = recipe.get("bodyDrivenSizing", {})
    if body_sizing_policy and not isinstance(body_sizing_policy, dict):
        raise ValueError("bodyDrivenSizing must be an object")
    prepared_source_rows = {
        int(value)
        for value in recipe.get("calibrationPreparedSourceRows", [])
    }
    for direction_row, direction in enumerate(DIRECTIONS):
        direction_scale = int(
            direction_scale_overrides.get(direction, calibration_scale)
        )
        if direction_scale < 50 or direction_scale > 200:
            raise ValueError(
                f"{recipe['identityId']} {direction} scale must be "
                "between 50 and 200"
            )
        scale_factor = direction_scale / 100.0
        client_maximum_size = baseline["directionRuntimeTargetSize"][direction]
        maximum_size = [
            max(1, round(float(value) * scale_factor))
            for value in client_maximum_size
        ]
        target_mass = float(
            baseline["directionRuntimeOpaquePixels"][direction]
        ) * scale_factor * scale_factor
        cutout = cutouts[direction]
        body_sizing_record = {}
        if body_sizing_policy:
            variant, body_sizing_record = fit_body_to_client_envelope(
                cutout,
                maximum_size,
                target_mass,
                body_sizing_policy,
            )
        else:
            variant = fit_to_client_envelope(
                cutout,
                maximum_size,
                target_mass,
            )
        source_slot = canonical_slots[direction_row]
        excluded_accessory = str(
            body_sizing_policy.get(
                "excludedAccessory",
                "two_long_lateral_horns",
            )
        )
        prepared_policy = (
            "concept_body_driven_resize_horns_excluded_v1"
            if (
                body_sizing_policy
                and excluded_accessory == "two_long_lateral_horns"
            )
            else (
                "concept_body_driven_resize_accessory_excluded_v1"
                if body_sizing_policy
                else "concept_direct_resize"
            )
        )
        if bool(recipe.get("despillGreenCutouts", False)):
            prepared_policy += "_source_green_despill"
        if source_slot in prepared_source_rows:
            variant = despill_green_matte(variant)
            prepared_policy = "concept_direct_resize_green_despill_v1"
        diameter_record = {}
        if diameter_policy:
            variant, diameter_record = project_horizontal_diameter(
                variant,
                direction,
                diameter_policy,
            )
            prepared_policy += "_angle_aware_diameter_projection"
        variants[direction] = variant
        record = {
            "sourceSlot": source_slot,
            "sourceCutoutSize": [cutout.width, cutout.height],
            "sourceCutoutRgbaSha256": rgba_sha256(cutout),
            "generatedSize": [variant.width, variant.height],
            "generatedRgbaSha256": rgba_sha256(variant),
            "effectiveOpaquePixels": round(
                effective_opaque_pixels(variant),
                4,
            ),
            "clientMedianEnvelope": list(client_maximum_size),
            "clientMedianOpaquePixels": round(
                target_mass / (scale_factor * scale_factor), 4
            ),
            "calibrationBaseScalePercent": calibration_scale,
            "calibrationDirectionScalePercent": direction_scale,
            "calibrationEnvelope": list(maximum_size),
            "preparedPixelPolicy": prepared_policy,
            "angleAwareHorizontalDiameter": diameter_record,
        }
        if body_sizing_record:
            record["bodyDrivenSizing"] = body_sizing_record
        records[direction] = record
    return variants, records, acceptance


def pose_anchor_map(baseline: dict) -> dict[tuple[str, int, int], dict]:
    records = {
        (action, int(record["directionRow"]), int(record["frame"])): record
        for action, action_records in baseline.get("poseAnchors", {}).items()
        for record in action_records
    }
    expected = sum(
        8 * int(spec["frames"]) for spec in ACTION_SPECS.values()
    )
    if len(records) != expected:
        raise AssertionError(
            f"same-frame head anchor table is incomplete: "
            f"{len(records)} != {expected}"
        )
    return records


def hair_frame_record(
    library: tuple,
    source_index: int,
) -> dict:
    data, palette, offsets, _info = library
    image, metadata = decode_sprite(
        data,
        offsets[source_index],
        palette,
    )
    rgba = image.convert("RGBA")
    return {
        "sourceIndex": source_index,
        "hot": [int(metadata["x"]), int(metadata["y"])],
        "sourceSize": [rgba.width, rgba.height],
        "sourceRgbaSha256": rgba_sha256(rgba),
    }


def cell_box(frame: int, direction: int) -> tuple[int, int, int, int]:
    return (
        frame * CELL[0],
        direction * CELL[1],
        (frame + 1) * CELL[0],
        (direction + 1) * CELL[1],
    )


def save_deterministic_atlas(
    path: Path,
    atlas: Image.Image,
    preserve: bool = False,
) -> None:
    if path.exists():
        existing = Image.open(path).convert("RGBA")
        if existing.size == atlas.size and existing.tobytes() == atlas.tobytes():
            return
        if preserve:
            raise AssertionError(f"accepted atlas changed: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(path, format="PNG", optimize=False)


def build_generated_action(
    recipe: dict,
    variants: dict[str, Image.Image],
    variant_records: dict[str, dict],
    anchors: dict[tuple[str, int, int], dict],
    hair_library: tuple,
    action_name: str,
) -> dict:
    frame_count = int(ACTION_SPECS[action_name]["frames"])
    atlas = Image.new(
        "RGBA",
        (CELL[0] * frame_count, CELL[1] * 8),
        (0, 0, 0, 0),
    )
    frames: list[dict] = []
    for direction_row, direction in enumerate(DIRECTIONS):
        helmet = variants[direction]
        cutout_record = variant_records[direction]
        for frame in range(frame_count):
            anchor = anchors[(action_name, direction_row, frame)]
            anchor_center = [
                round(float(anchor["centroidMedian"][0])),
                round(float(anchor["centroidMedian"][1])),
            ]
            hair_center = [
                float(anchor["hairAnchorCentroid"][0]),
                float(anchor["hairAnchorCentroid"][1]),
            ]
            head_distance = math.dist(anchor_center, hair_center)
            if head_distance > 10.0:
                raise AssertionError(
                    f"{recipe['identityId']} {action_name} {direction} "
                    f"F{frame} anchor is {head_distance:.3f}px from Hair.wil"
                )
            paste = [
                anchor_center[0] - helmet.width // 2,
                anchor_center[1] - helmet.height // 2,
            ]
            if (
                paste[0] < 0
                or paste[1] < 0
                or paste[0] + helmet.width > CELL[0]
                or paste[1] + helmet.height > CELL[1]
            ):
                raise AssertionError(
                    f"{recipe['identityId']} {action_name} {direction} "
                    f"F{frame} clips the actor cell"
                )
            atlas.alpha_composite(
                helmet,
                (
                    frame * CELL[0] + paste[0],
                    direction_row * CELL[1] + paste[1],
                ),
            )
            cell = atlas.crop(cell_box(frame, direction_row))
            if any(
                cell.getpixel(point)[3] != 0
                for point in (
                    (0, 0),
                    (CELL[0] - 1, 0),
                    (0, CELL[1] - 1),
                    (CELL[0] - 1, CELL[1] - 1),
                )
            ):
                raise AssertionError("helmet atlas cell corner is not transparent")
            hair = hair_frame_record(
                hair_library,
                int(anchor["hairAnchorSourceIndex"]),
            )
            frames.append(
                {
                    "direction": direction,
                    "directionRow": direction_row,
                    "frame": frame,
                    "hairFrame": hair,
                    "hairAnchorCentroid": [
                        round(hair_center[0], 4),
                        round(hair_center[1], 4),
                    ],
                    "helmetAnchorCentroid": anchor_center,
                    "headDistancePixels": round(head_distance, 4),
                    "selectedHelmetWilAppearances": list(
                        anchor["selectedAppearances"]
                    ),
                    "rejectedHelmetWilAppearances": list(
                        anchor["outlierAppearances"]
                    ),
                    "paste": paste,
                    "generatedSize": [helmet.width, helmet.height],
                    "conceptCutoutRgbaSha256": cutout_record[
                        "sourceCutoutRgbaSha256"
                    ],
                    "generatedHelmetRgbaSha256": cutout_record[
                        "generatedRgbaSha256"
                    ],
                    "cellRgbaSha256": rgba_sha256(cell),
                    "pixelSource": str(recipe["concept"]),
                    "poseVariant": "concept-sheet-direct-resize",
                    "stateItemPixelsUsed": False,
                    "hairPixelsUsed": False,
                }
            )
    target = disk_path(
        f"{recipe['outputPrefix']}_{action_name}.png"
    )
    save_deterministic_atlas(target, atlas)
    return {
        "path": resource_path(target),
        "fileSha256": file_sha256(target),
        "atlasRgbaSha256": rgba_sha256(atlas),
        "cell": list(CELL),
        "footAnchor": list(FOOT_ANCHOR),
        "directions": 8,
        "framesPerDirection": frame_count,
        "physicalCellCount": 8 * frame_count,
        "missingFrames": [],
        "confidence": "project_approved_exact",
        "frames": frames,
    }


def normalize_black_iron_identity(
    recipe: dict,
    variants: dict[str, Image.Image],
    variant_records: dict[str, dict],
    direction_acceptance: dict,
    anchors: dict[tuple[str, int, int], dict],
    hair_library: tuple,
) -> dict:
    source = load_json(BLACK_IRON_SOURCE)
    if int(source.get("schemaVersion", 0)) != 16:
        raise AssertionError("Black Iron Helmet provenance was not upgraded to v16")
    actions: dict[str, dict] = {}
    for action_name, spec in ACTION_SPECS.items():
        source_action = source.get("actions", {}).get(action_name, {})
        frame_count = int(spec["frames"])
        path = disk_path(str(source_action.get("path", "")))
        atlas = Image.open(path).convert("RGBA")
        if atlas.size != (CELL[0] * frame_count, CELL[1] * 8):
            raise AssertionError(
                f"Black Iron Helmet {action_name} atlas size changed"
            )
        source_frames = {
            (int(record["direction"]), int(record["frame"])): record
            for record in source_action.get("frames", [])
        }
        if len(source_frames) != 8 * frame_count:
            raise AssertionError(
                f"Black Iron Helmet {action_name} provenance is incomplete"
            )
        frames: list[dict] = []
        for direction_row, direction in enumerate(DIRECTIONS):
            variant_record = variant_records[direction]
            for frame in range(frame_count):
                record = source_frames[(direction_row, frame)]
                anchor = anchors[(action_name, direction_row, frame)]
                helmet_center = [
                    float(record["helmetAnchorCentroid"][0]),
                    float(record["helmetAnchorCentroid"][1]),
                ]
                hair_center = [
                    float(record["hairAnchorCentroid"][0]),
                    float(record["hairAnchorCentroid"][1]),
                ]
                head_distance = math.dist(helmet_center, hair_center)
                if head_distance > 10.0:
                    raise AssertionError(
                        f"Black Iron Helmet {action_name} {direction} "
                        f"F{frame} is {head_distance:.3f}px from Hair.wil"
                    )
                cell = atlas.crop(cell_box(frame, direction_row))
                hair = hair_frame_record(
                    hair_library,
                    int(anchor["hairAnchorSourceIndex"]),
                )
                frames.append(
                    {
                        "direction": direction,
                        "directionRow": direction_row,
                        "frame": frame,
                        "hairFrame": hair,
                        "hairAnchorCentroid": [
                            round(hair_center[0], 4),
                            round(hair_center[1], 4),
                        ],
                        "helmetAnchorCentroid": [
                            round(helmet_center[0], 4),
                            round(helmet_center[1], 4),
                        ],
                        "headDistancePixels": round(head_distance, 4),
                        "selectedHelmetWilAppearances": list(
                            record["selectedAnchorAppearances"]
                        ),
                        "rejectedHelmetWilAppearances": list(
                            record["rejectedAnchorAppearances"]
                        ),
                        "paste": list(record["paste"]),
                        "generatedSize": list(record["generatedSize"]),
                        "conceptCutoutRgbaSha256": variant_record[
                            "sourceCutoutRgbaSha256"
                        ],
                        "generatedHelmetRgbaSha256": (
                            variant_record["generatedRgbaSha256"]
                            if action_name != "death"
                            else rgba_sha256(
                                cell.crop(cell.getchannel("A").getbbox())
                            )
                        ),
                        "cellRgbaSha256": rgba_sha256(cell),
                        "pixelSource": (
                            str(recipe["concept"])
                            if action_name != "death"
                            else str(
                                source["approvedDirectionReferences"][
                                    "godotRenderManifest"
                                ]
                            )
                        ),
                        "poseVariant": str(record["poseVariant"]),
                        "stateItemPixelsUsed": False,
                        "hairPixelsUsed": False,
                    }
                )
        actions[action_name] = {
            "path": resource_path(path),
            "fileSha256": file_sha256(path),
            "atlasRgbaSha256": rgba_sha256(atlas),
            "cell": list(CELL),
            "footAnchor": list(FOOT_ANCHOR),
            "directions": 8,
            "framesPerDirection": frame_count,
            "physicalCellCount": 8 * frame_count,
            "missingFrames": [],
            "confidence": "project_approved_exact",
            "frames": frames,
        }
    return {
        "identityId": "black_iron",
        "sourceIndex": int(recipe["sourceIndex"]),
        "sex": "male",
        "concept": str(recipe["concept"]),
        "conceptFileSha256": file_sha256(disk_path(str(recipe["concept"]))),
        "sourceGrid": list(recipe["sourceGrid"]),
        "sourceSlotDirectionOrder": list(
            recipe["sourceSlotDirectionOrder"]
        ),
        "canonicalRowSourceSlots": list(
            recipe["canonicalRowSourceSlots"]
        ),
        "directionAcceptance": direction_acceptance,
        "directionCutouts": variant_records,
        "acceptedLegacyAtlasPreserved": sorted(
            BLACK_IRON_PRESERVED_ACTIONS
        ),
        "stateItemPixelsUsed": False,
        "hairPixelsUsed": False,
        "actions": actions,
    }


def build_black_iron_and_lock_accepted_atlases() -> dict[str, str]:
    root = ROOT / "assets/art/characters/warrior/wear/helmet"
    before = {
        action: file_sha256(root / f"black_iron_helmet_{action}.png")
        for action in BLACK_IRON_PRESERVED_ACTIONS
    }
    from build_world_helmet_asset import main as build_black_iron

    build_black_iron()
    after = {
        action: file_sha256(root / f"black_iron_helmet_{action}.png")
        for action in BLACK_IRON_PRESERVED_ACTIONS
    }
    if before != after:
        raise AssertionError("one of the five accepted Black Iron atlases changed")
    return after


def appearance_for_identity(identity: dict) -> dict:
    return {
        "sex": "male",
        "visible": True,
        "identityId": str(identity["identityId"]),
        "identityRef": (
            f"visualIdentities.{identity['identityId']}"
        ),
        "actions": {
            action_name: {
                "identityActionRef": (
                    f"visualIdentities.{identity['identityId']}."
                    f"actions.{action_name}"
                ),
                "path": str(action["path"]),
                "cell": list(CELL),
                "footAnchor": list(FOOT_ANCHOR),
                "directions": 8,
                "framesPerDirection": int(
                    action["framesPerDirection"]
                ),
                "missingFrames": [],
                "confidence": "project_approved_exact",
            }
            for action_name, action in identity["actions"].items()
        },
        "actionFallbacks": {},
    }


def build_contract() -> dict:
    recipes = load_json(RECIPES)
    if recipes.get("contractId") != CONTRACT_ID:
        raise AssertionError("world helmet recipe contract id changed")
    if recipes.get("sex") != "male":
        raise AssertionError("world helmet recipes must remain male-only")
    if list(recipes["actorContract"]["directions"]) != DIRECTIONS:
        raise AssertionError("canonical direction order changed")
    if recipes["actorContract"]["actions"] != ACTION_SPECS:
        raise AssertionError("six-action recipe table changed")

    from analyze_client_helmet_parameters import main as rebuild_baseline

    rebuild_baseline()
    baseline = load_json(CLIENT_BASELINE)
    anchors = pose_anchor_map(baseline)
    hair_library = read_library(HAIR_SOURCE)
    _hair_data, _hair_palette, _hair_offsets, hair_info = hair_library
    if int(hair_info["image_count"]) <= HAIR_APPEARANCE * HAIR_STRIDE + 599:
        raise AssertionError("Hair.wil does not contain the male anchor family")

    accepted_black_iron_shas = build_black_iron_and_lock_accepted_atlases()
    identity_recipes = {
        str(recipe["identityId"]): recipe
        for recipe in recipes["identities"]
    }
    if len(identity_recipes) != 11:
        raise AssertionError("world helmet recipes must contain 11 identities")
    missing_concepts = [
        str(recipe["concept"])
        for recipe in identity_recipes.values()
        if not disk_path(str(recipe["concept"])).exists()
    ]
    if missing_concepts:
        raise FileNotFoundError(
            "missing approved helmet concepts:\n"
            + "\n".join(missing_concepts)
        )

    identities: dict[str, dict] = {}
    for identity_id, recipe in identity_recipes.items():
        variants, variant_records, direction_acceptance = build_variants(
            recipe,
            baseline,
        )
        if identity_id == "black_iron":
            identities[identity_id] = normalize_black_iron_identity(
                recipe,
                variants,
                variant_records,
                direction_acceptance,
                anchors,
                hair_library,
            )
            continue
        actions = {
            action_name: build_generated_action(
                recipe,
                variants,
                variant_records,
                anchors,
                hair_library,
                action_name,
            )
            for action_name in ACTION_SPECS
        }
        identities[identity_id] = {
            "identityId": identity_id,
            "sourceIndex": int(recipe["sourceIndex"]),
            "sex": "male",
            "concept": str(recipe["concept"]),
            "conceptFileSha256": file_sha256(
                disk_path(str(recipe["concept"]))
            ),
            "sourceGrid": list(recipe["sourceGrid"]),
            "sourceSlotDirectionOrder": list(
                recipe["sourceSlotDirectionOrder"]
            ),
            "canonicalRowSourceSlots": list(
                recipe["canonicalRowSourceSlots"]
            ),
            "directionAcceptance": direction_acceptance,
            "directionCutouts": variant_records,
            "calibrationPreparedSourceRows": list(
                recipe.get("calibrationPreparedSourceRows", [])
            ),
            "stateItemPixelsUsed": False,
            "hairPixelsUsed": False,
            "actions": actions,
        }
        identities[identity_id].update(calibration_source_metadata(recipe))

    existing_catalog = load_json(VISUAL_CATALOG)
    item_recipes = {
        str(int(item["itemId"])): item for item in recipes["items"]
    }
    if {int(item_id) for item_id in item_recipes} != EXPECTED_ITEM_IDS:
        raise AssertionError("formal world helmet item ids changed")
    items: dict[str, dict] = {}
    runtime_by_item_id: dict[str, dict] = {}
    for item_key, item in item_recipes.items():
        catalog_item = existing_catalog["itemsById"].get(item_key, {})
        if str(catalog_item.get("itemName", "")) != str(item["itemName"]):
            raise AssertionError(f"catalog name mismatch for item {item_key}")
        paper = catalog_item.get("paperDoll", {})
        if int(paper.get("sourceIndex", -1)) != int(item["sourceIndex"]):
            raise AssertionError(
                f"StateItem identity mismatch for item {item_key}"
            )
        identity_id = str(item["identityId"])
        identity = identities[identity_id]
        if int(identity["sourceIndex"]) != int(item["sourceIndex"]):
            raise AssertionError(
                f"recipe identity sourceIndex mismatch for item {item_key}"
            )
        appearance = appearance_for_identity(identity)
        record = {
            "itemId": int(item_key),
            "itemName": str(item["itemName"]),
            "sourceIndex": int(item["sourceIndex"]),
            "identityId": identity_id,
            "identityRef": f"visualIdentities.{identity_id}",
            "sex": "male",
            "slot": "helmet",
            "status": "approved_project_extension",
            "identityEvidence": {
                "library": "StateItem.wil",
                "sourceIndex": int(item["sourceIndex"]),
                "usage": "visual identity only; no runtime pixels copied",
                "stateItemPixelsUsed": False,
            },
            "maleAppearance": appearance,
        }
        items[item_key] = record
        runtime_by_item_id[item_key] = {
            "helmetAppearance": deepcopy(appearance)
        }

    physical_cells = sum(
        int(action["physicalCellCount"])
        for identity in identities.values()
        for action in identity["actions"].values()
    )
    logical_cells = sum(
        8 * sum(int(spec["frames"]) for spec in ACTION_SPECS.values())
        for _item in items.values()
    )
    payload = {
        "schemaVersion": 1,
        "contractId": CONTRACT_ID,
        "sex": "male",
        "recipe": resource_path(RECIPES),
        "recipeFileSha256": file_sha256(RECIPES),
        "actorContract": {
            "contractId": "player.visual.classic_eight_direction.v1",
            "cell": list(CELL),
            "footAnchor": list(FOOT_ANCHOR),
            "directions": DIRECTIONS,
            "actions": ACTION_SPECS,
            "footPointContractChanged": False,
        },
        "sourcePolicy": {
            "classification": "project-generated extension",
            "stateItemUsage": "identity evidence only",
            "stateItemPixelsUsed": False,
            "hairUsage": (
                "same action, direction and frame head anchor only"
            ),
            "hairPixelsUsed": False,
            "runtimePixelSource": (
                "approved eight-direction concept sheet, except the already "
                "accepted Black Iron death geometry"
            ),
            "background": "transparent",
            "femaleExcluded": True,
            "actionFallbacks": {},
        },
        "sourceEvidence": {
            "hairLibrary": resource_path(HAIR_SOURCE),
            "hairLibraryFileSha256": file_sha256(HAIR_SOURCE),
            "hairAppearance": HAIR_APPEARANCE,
            "hairStride": HAIR_STRIDE,
            "clientHelmetParameterBaseline": resource_path(CLIENT_BASELINE),
            "clientHelmetParameterBaselineFileSha256": file_sha256(
                CLIENT_BASELINE
            ),
            "poseAnchorRecords": len(anchors),
            "poseAnchorMaximumHeadDistancePixels": 10.0,
            "visualMassTargetMultiplier": VISUAL_MASS_TARGET_MULTIPLIER,
        },
        "coverage": {
            "formalHelmetItems": len(items),
            "visualIdentities": len(identities),
            "actionsPerIdentity": len(ACTION_SPECS),
            "directionsPerAction": 8,
            "physicalAtlasCells": physical_cells,
            "logicalItemCells": logical_cells,
            "missingFrames": 0,
            "maleItems": len(items),
            "femaleItems": 0,
            "acceptedBlackIronAtlasesPreserved": len(
                accepted_black_iron_shas
            ),
        },
        "acceptedBlackIronAtlasFileSha256": accepted_black_iron_shas,
        "visualIdentities": identities,
        "itemsById": items,
        "runtimeMappingsByItemId": runtime_by_item_id,
    }
    validate_contract(payload)
    CONTRACT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload


def rebuild_generated_identity(identity_id: str) -> dict:
    """Rebuild one non-Black-Iron identity without touching other helmets."""
    if identity_id == "black_iron":
        raise ValueError(
            "targeted rebuild does not bypass Black Iron evidence requirements"
        )
    recipes = load_json(RECIPES)
    if recipes.get("contractId") != CONTRACT_ID:
        raise AssertionError("world helmet recipe contract id changed")
    identity_recipes = {
        str(recipe["identityId"]): recipe
        for recipe in recipes["identities"]
    }
    if identity_id not in identity_recipes:
        raise KeyError(f"unknown helmet identity: {identity_id}")
    recipe = identity_recipes[identity_id]
    concept_path = disk_path(str(recipe["concept"]))
    if not concept_path.exists():
        raise FileNotFoundError(f"missing approved helmet concept: {concept_path}")

    baseline = load_json(CLIENT_BASELINE)
    anchors = pose_anchor_map(baseline)
    hair_library = read_library(HAIR_SOURCE)
    _hair_data, _hair_palette, _hair_offsets, hair_info = hair_library
    if int(hair_info["image_count"]) <= HAIR_APPEARANCE * HAIR_STRIDE + 599:
        raise AssertionError("Hair.wil does not contain the male anchor family")

    variants, variant_records, direction_acceptance = build_variants(
        recipe,
        baseline,
    )
    actions = {
        action_name: build_generated_action(
            recipe,
            variants,
            variant_records,
            anchors,
            hair_library,
            action_name,
        )
        for action_name in ACTION_SPECS
    }
    identity = {
        "identityId": identity_id,
        "sourceIndex": int(recipe["sourceIndex"]),
        "sex": "male",
        "concept": str(recipe["concept"]),
        "conceptFileSha256": file_sha256(concept_path),
        "sourceGrid": list(recipe["sourceGrid"]),
        "sourceSlotDirectionOrder": list(
            recipe["sourceSlotDirectionOrder"]
        ),
        "canonicalRowSourceSlots": list(
            recipe["canonicalRowSourceSlots"]
        ),
        "directionAcceptance": direction_acceptance,
        "directionCutouts": variant_records,
        "calibrationPreparedSourceRows": list(
            recipe.get("calibrationPreparedSourceRows", [])
        ),
        "stateItemPixelsUsed": False,
        "hairPixelsUsed": False,
        "actions": actions,
    }
    identity.update(calibration_source_metadata(recipe))

    payload = load_json(CONTRACT)
    payload["recipeFileSha256"] = file_sha256(RECIPES)
    payload["visualIdentities"][identity_id] = identity
    for item in payload.get("itemsById", {}).values():
        if str(item.get("identityId", "")) != identity_id:
            continue
        appearance = appearance_for_identity(identity)
        item["maleAppearance"] = appearance
        payload["runtimeMappingsByItemId"][str(item["itemId"])] = {
            "helmetAppearance": deepcopy(appearance)
        }
    validate_contract(payload)
    CONTRACT.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return payload


def validate_contract(contract: dict) -> None:
    if contract.get("contractId") != CONTRACT_ID:
        raise AssertionError("world helmet contract id changed")
    if contract.get("sex") != "male":
        raise AssertionError("world helmet contract is not male-only")
    coverage = contract.get("coverage", {})
    expected_coverage = {
        "formalHelmetItems": 12,
        "visualIdentities": 11,
        "actionsPerIdentity": 6,
        "directionsPerAction": 8,
        "physicalAtlasCells": 2552,
        "logicalItemCells": 2784,
        "missingFrames": 0,
        "maleItems": 12,
        "femaleItems": 0,
        "acceptedBlackIronAtlasesPreserved": 5,
    }
    if coverage != expected_coverage:
        raise AssertionError(
            f"world helmet coverage changed: {coverage}"
        )
    if contract.get("sourcePolicy", {}).get("stateItemPixelsUsed") is not False:
        raise AssertionError("StateItem pixels are allowed by the contract")
    if contract.get("sourcePolicy", {}).get("hairPixelsUsed") is not False:
        raise AssertionError("Hair pixels are allowed by the contract")
    identities = contract.get("visualIdentities", {})
    if len(identities) != 11:
        raise AssertionError("world helmet identity count changed")
    for identity_id, identity in identities.items():
        if identity.get("sex") != "male":
            raise AssertionError(f"{identity_id} is not male-only")
        if identity.get("stateItemPixelsUsed") is not False:
            raise AssertionError(f"{identity_id} claims StateItem pixels")
        if set(identity.get("actions", {})) != set(ACTION_SPECS):
            raise AssertionError(f"{identity_id} lacks a physical action")
        calibration_source = str(
            identity.get("calibrationSourceSheet", "")
        )
        if calibration_source:
            calibration_path = disk_path(calibration_source)
            if not calibration_path.exists():
                raise AssertionError(
                    f"{identity_id} calibration source is missing"
                )
            if file_sha256(calibration_path) != str(
                identity.get("calibrationSourceSheetSha256", "")
            ):
                raise AssertionError(
                    f"{identity_id} calibration source SHA changed"
                )
            if identity.get("calibrationPreparedSourceRows", []) != []:
                raise AssertionError(
                    f"{identity_id} calibration source has a low-resolution "
                    "prepared-row exception"
                )
        slot_order = list(identity.get("sourceSlotDirectionOrder", []))
        canonical_slots = [
            int(value)
            for value in identity.get("canonicalRowSourceSlots", [])
        ]
        if len(slot_order) != 8 or sorted(slot_order) != sorted(DIRECTIONS):
            raise AssertionError(
                f"{identity_id} lacks eight manually classified source slots"
            )
        if canonical_slots != [
            slot_order.index(direction) for direction in DIRECTIONS
        ]:
            raise AssertionError(
                f"{identity_id} canonical rows do not use classified slots"
            )
        acceptance = identity.get("directionAcceptance", {})
        acceptance_path = disk_path(str(acceptance.get("path", "")))
        if (
            acceptance.get("classificationStatus")
            != "accepted_manual_visual_classification"
            or not str(acceptance.get("classificationEvidence", "")).strip()
            or file_sha256(acceptance_path)
            != acceptance.get("fileSha256")
        ):
            raise AssertionError(
                f"{identity_id} direction acceptance is incomplete"
            )
        for action_name, spec in ACTION_SPECS.items():
            action = identity["actions"][action_name]
            path = disk_path(str(action["path"]))
            atlas = Image.open(path).convert("RGBA")
            expected_size = (
                CELL[0] * int(spec["frames"]),
                CELL[1] * 8,
            )
            if atlas.size != expected_size:
                raise AssertionError(
                    f"{identity_id} {action_name} atlas size changed"
                )
            if rgba_sha256(atlas) != action["atlasRgbaSha256"]:
                raise AssertionError(
                    f"{identity_id} {action_name} atlas RGBA SHA changed"
                )
            if file_sha256(path) != action["fileSha256"]:
                raise AssertionError(
                    f"{identity_id} {action_name} file SHA changed"
                )
            frames = action.get("frames", [])
            if len(frames) != 8 * int(spec["frames"]):
                raise AssertionError(
                    f"{identity_id} {action_name} provenance is incomplete"
                )
            for record in frames:
                direction = int(record["directionRow"])
                frame = int(record["frame"])
                cell = atlas.crop(cell_box(frame, direction))
                if rgba_sha256(cell) != record["cellRgbaSha256"]:
                    raise AssertionError(
                        f"{identity_id} {action_name} d{direction} "
                        f"f{frame} cell SHA changed"
                    )
                if float(record["headDistancePixels"]) > 10.0:
                    raise AssertionError(
                        f"{identity_id} {action_name} head distance changed"
                    )
                if record.get("stateItemPixelsUsed") is not False:
                    raise AssertionError("frame claims StateItem pixels")
                for point in (
                    (0, 0),
                    (CELL[0] - 1, 0),
                    (0, CELL[1] - 1),
                    (CELL[0] - 1, CELL[1] - 1),
                ):
                    if cell.getpixel(point)[3] != 0:
                        raise AssertionError(
                            f"{identity_id} {action_name} corner is opaque"
                        )
    items = contract.get("itemsById", {})
    if {int(item_id) for item_id in items} != EXPECTED_ITEM_IDS:
        raise AssertionError("world helmet item ids changed")
    if (
        items["147"]["identityId"] != "bronze_magic"
        or items["148"]["identityId"] != "bronze_magic"
    ):
        raise AssertionError("Bronze and Magic Helmet must share one identity")
    if (
        items["147"]["maleAppearance"]
        != items["148"]["maleAppearance"]
    ):
        raise AssertionError("Bronze and Magic Helmet atlas mapping diverged")
    for item in items.values():
        appearance = item["maleAppearance"]
        if appearance.get("sex") != "male":
            raise AssertionError("item appearance is not male-only")
        if appearance.get("actionFallbacks") != {}:
            raise AssertionError("world helmet action fallback was introduced")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate the committed contract and atlases without rebuilding",
    )
    parser.add_argument(
        "--identity",
        help=(
            "rebuild one generated visual identity without rebuilding "
            "Black Iron or unrelated helmets"
        ),
    )
    args = parser.parse_args()
    if args.validate_only:
        validate_contract(load_json(CONTRACT))
        payload = load_json(CONTRACT)
    elif args.identity:
        payload = rebuild_generated_identity(str(args.identity))
    else:
        payload = build_contract()
    coverage = payload["coverage"]
    print(
        "EQUIPMENT_MALE_WORLD_HELMET_PASS "
        f"items={coverage['formalHelmetItems']} "
        f"identities={coverage['visualIdentities']} "
        f"actions={coverage['actionsPerIdentity']} "
        f"directions={coverage['directionsPerAction']} "
        f"logical_cells={coverage['logicalItemCells']} "
        "stateitem_world_pixels=0 female=0"
    )


if __name__ == "__main__":
    main()
