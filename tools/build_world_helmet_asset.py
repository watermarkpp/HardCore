#!/usr/bin/env python3
"""Build the evidence-calibrated Black Iron Helmet world animation layer.

One complete client was scanned frame-by-frame and its paired runtime source
was audited.  The verified classic item exists as StateItem #344, but the 2013
runtime only draws Hair appearances and contains no matching worn Black Iron
Helmet layer.  StateItem #344 remains the verified equipment-window identity,
while the approved redesign is reconstructed as one complete procedural helmet
and rendered by Godot's orthographic 3D pipeline.  The source Hair animation is
used only as a per-frame head-motion anchor.  Death uses a 32-cell pose table
calibrated from the matching body direction/frame, Hair anchor and six authored
Helmet.wil appearances.  No Hair, unrelated Helmet, or old StateItem-derived
world pixels are copied into the generated result.  For standing/action views,
the user-approved eight-view design is used directly after grey-background
removal and aspect-preserving resize; death remains a same-cell Godot pose
render because the approved sheet contains no fallen views.
"""

from __future__ import annotations

import hashlib
import json
import math
import statistics
import sys
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ICON = ROOT / "assets/art/characters/warrior/paper_doll/classic/layers/stateitem_00344.png"
APPROVED_CONCEPT = (
    ROOT
    / "assets/art/characters/warrior/wear/helmet/source"
    / "black_iron_helmet_approved_meteoric_narrow_jaw_20260717.png"
)
DIRECT_DESIGN_ROOT = ROOT / "outputs/visual_acceptance/black_iron_helmet_direct_design"
GODOT_RENDER_ROOT = ROOT / "outputs/visual_acceptance/black_iron_helmet_3d"
GODOT_RENDER_MANIFEST = GODOT_RENDER_ROOT / "manifest.json"
DEATH_POSE_BASELINE = ROOT / "outputs/resource_catalog/black_iron_helmet/death_pose_baseline.json"
ANCHOR_SOURCE = ROOT / "dev_art_sources/external/mir2opensource_full/Data/Hair.wil"
SOURCE_CODE = ROOT / "dev_art_sources/reference/mir2opensource_2013_client/MirObjects/PlayerObject.cs"
FRAME_CODE = ROOT / "dev_art_sources/reference/mir2opensource_2013_client/MirObjects/Frames.cs"
COMPLETE_SCAN = ROOT / "outputs/resource_catalog/complete_client_frame_catalog/manifest.json"
CLIENT_HELMET_BASELINE = ROOT / "outputs/resource_catalog/black_iron_helmet/client_helmet_parameter_baseline.json"
OUTPUT = ROOT / "assets/art/characters/warrior/wear/helmet"
PROVENANCE = OUTPUT / "black_iron_helmet.source.json"
ANCHOR_APPEARANCE = 2
ANCHOR_STRIDE = 2224
CELL = (192, 160)
SOURCE_DRAW_ORIGIN = (64, 80)
RUNTIME_ENVELOPE_SCALE = 1.0
VISUAL_MASS_TARGET_MULTIPLIER = 1.15
CANONICAL_DIRECTIONS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
# The approved sheet is not laid out in canonical game-row order. These labels
# were assigned from visible front aperture, jaw projection and rear shell for
# every source slot; game rows must select by label instead of zip order.
APPROVED_SOURCE_SLOT_DIRECTIONS = ["N", "E", "W", "SW", "S", "SE", "NW", "NE"]
CANONICAL_ROW_SOURCE_SLOTS = [
    APPROVED_SOURCE_SLOT_DIRECTIONS.index(direction)
    for direction in CANONICAL_DIRECTIONS
]
ACTIONS = {
    "idle": {"start": 0, "frames": 4},
    "walk": {"start": 64, "frames": 6},
    "attack": {"start": 200, "frames": 6},
    "cast": {"start": 392, "frames": 6},
    "hit": {"start": 472, "frames": 3},
    "death": {"start": 536, "frames": 4},
}

sys.path.insert(0, str(ROOT / "tools/vendor"))
from extract_wil import decode_sprite, read_library  # noqa: E402


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


MATTE_PALETTE = (
    (8, 8, 8, 255),
    (15, 15, 15, 255),
    (23, 23, 23, 255),
    (32, 32, 32, 255),
    (43, 43, 43, 255),
    (56, 56, 56, 255),
)

PIXEL_OUTLINE = (8, 8, 8, 255)
PIXEL_CAVITY = (3, 3, 3, 255)
PIXEL_SHADOW = (20, 20, 20, 255)
PIXEL_DARK = (30, 30, 30, 255)
PIXEL_MID = (42, 42, 42, 255)
PIXEL_LIGHT = (56, 56, 56, 255)
PIXEL_EDGE = (68, 68, 68, 255)


def _points(size: tuple[int, int], values: list[tuple[float, float]]) -> list[tuple[int, int]]:
    width, height = size
    return [(round(x * (width - 1)), round(y * (height - 1))) for x, y in values]


def _polygon(
    draw: ImageDraw.ImageDraw,
    size: tuple[int, int],
    values: list[tuple[float, float]],
    fill: tuple[int, int, int, int],
    outline: tuple[int, int, int, int] | None = PIXEL_OUTLINE,
) -> None:
    draw.polygon(_points(size, values), fill=fill, outline=outline)


def _line(
    draw: ImageDraw.ImageDraw,
    size: tuple[int, int],
    values: list[tuple[float, float]],
    fill: tuple[int, int, int, int],
    width: int = 1,
) -> None:
    draw.line(_points(size, values), fill=fill, width=width)


def _meteor_texture(image: Image.Image, seed: int) -> None:
    """Add a few deliberate forged-iron clusters without obscuring plate seams."""
    pixels = image.load()
    alpha = image.getchannel("A")
    for y in range(2, image.height - 2):
        for x in range(2, image.width - 2):
            if alpha.getpixel((x, y)) < 128 or (x * 17 + y * 31 + seed * 13) % 43 != 0:
                continue
            if all(alpha.getpixel((x + dx, y + dy)) >= 128 for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))):
                pixels[x, y] = PIXEL_SHADOW
                if x + 1 < image.width and alpha.getpixel((x + 1, y)) >= 128:
                    pixels[x + 1, y] = PIXEL_LIGHT


def _draw_front(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outer = [
        (0.28, 0.00), (0.72, 0.00), (0.91, 0.15), (1.00, 0.38),
        (0.96, 0.77), (0.73, 0.95), (0.62, 1.00), (0.38, 1.00),
        (0.27, 0.95), (0.04, 0.77), (0.00, 0.38), (0.09, 0.15),
    ]
    _polygon(draw, size, outer, PIXEL_MID)
    _polygon(draw, size, [(0.09, 0.15), (0.28, 0.00), (0.48, 0.03), (0.48, 0.37), (0.08, 0.37)], PIXEL_DARK)
    _polygon(draw, size, [(0.52, 0.03), (0.72, 0.00), (0.91, 0.15), (0.92, 0.37), (0.52, 0.37)], PIXEL_SHADOW)
    _line(draw, size, [(0.50, 0.02), (0.50, 0.38)], PIXEL_EDGE)
    _polygon(draw, size, [(0.04, 0.35), (0.96, 0.35), (0.96, 0.47), (0.04, 0.47)], PIXEL_DARK)
    _polygon(draw, size, [(0.11, 0.41), (0.43, 0.41), (0.43, 0.48), (0.11, 0.48)], PIXEL_CAVITY, None)
    _polygon(draw, size, [(0.57, 0.41), (0.89, 0.41), (0.89, 0.48), (0.57, 0.48)], PIXEL_CAVITY, None)
    _polygon(draw, size, [(0.44, 0.36), (0.56, 0.36), (0.58, 0.83), (0.50, 0.91), (0.42, 0.83)], PIXEL_DARK)
    _polygon(draw, size, [(0.05, 0.49), (0.42, 0.49), (0.40, 0.86), (0.25, 0.94), (0.08, 0.78)], PIXEL_SHADOW)
    _polygon(draw, size, [(0.58, 0.49), (0.95, 0.49), (0.92, 0.78), (0.75, 0.94), (0.60, 0.86)], PIXEL_DARK)
    _line(draw, size, [(0.08, 0.76), (0.40, 0.86), (0.50, 0.94), (0.60, 0.86), (0.92, 0.76)], PIXEL_EDGE)
    _polygon(draw, size, [(0.31, 0.88), (0.69, 0.88), (0.62, 1.00), (0.38, 1.00)], PIXEL_SHADOW)
    _meteor_texture(image, 4)
    return image


def _draw_back(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outer = [
        (0.28, 0.00), (0.72, 0.00), (0.91, 0.15), (1.00, 0.38),
        (0.96, 0.77), (0.73, 0.95), (0.62, 1.00), (0.38, 1.00),
        (0.27, 0.95), (0.04, 0.77), (0.00, 0.38), (0.09, 0.15),
    ]
    _polygon(draw, size, outer, PIXEL_MID)
    _polygon(draw, size, [(0.09, 0.15), (0.28, 0.00), (0.48, 0.03), (0.48, 0.45), (0.06, 0.45)], PIXEL_DARK)
    _polygon(draw, size, [(0.52, 0.03), (0.72, 0.00), (0.91, 0.15), (0.94, 0.45), (0.52, 0.45)], PIXEL_SHADOW)
    _line(draw, size, [(0.50, 0.02), (0.50, 0.45)], PIXEL_EDGE)
    _polygon(draw, size, [(0.04, 0.45), (0.96, 0.45), (0.95, 0.58), (0.05, 0.58)], PIXEL_DARK)
    _polygon(draw, size, [(0.06, 0.59), (0.48, 0.59), (0.47, 0.88), (0.27, 0.95), (0.08, 0.77)], PIXEL_SHADOW)
    _polygon(draw, size, [(0.52, 0.59), (0.94, 0.59), (0.92, 0.77), (0.73, 0.95), (0.53, 0.88)], PIXEL_DARK)
    _line(draw, size, [(0.50, 0.59), (0.50, 0.90)], PIXEL_EDGE)
    _polygon(draw, size, [(0.31, 0.88), (0.69, 0.88), (0.62, 1.00), (0.38, 1.00)], PIXEL_SHADOW)
    _meteor_texture(image, 0)
    return image


def _draw_front_three_quarter(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outer = [
        (0.18, 0.05), (0.58, 0.00), (0.84, 0.11), (0.96, 0.31),
        (1.00, 0.72), (0.82, 0.91), (0.57, 1.00), (0.28, 0.94),
        (0.08, 0.73), (0.00, 0.35),
    ]
    _polygon(draw, size, outer, PIXEL_MID)
    _polygon(draw, size, [(0.18, 0.05), (0.58, 0.00), (0.55, 0.36), (0.03, 0.36)], PIXEL_DARK)
    _polygon(draw, size, [(0.58, 0.00), (0.84, 0.11), (0.96, 0.31), (0.55, 0.36)], PIXEL_SHADOW)
    _line(draw, size, [(0.58, 0.02), (0.55, 0.36)], PIXEL_EDGE)
    _polygon(draw, size, [(0.02, 0.34), (0.95, 0.34), (0.97, 0.47), (0.04, 0.47)], PIXEL_DARK)
    _polygon(draw, size, [(0.15, 0.41), (0.53, 0.41), (0.53, 0.48), (0.15, 0.48)], PIXEL_CAVITY, None)
    _polygon(draw, size, [(0.59, 0.40), (0.91, 0.40), (0.92, 0.47), (0.59, 0.47)], PIXEL_CAVITY, None)
    _polygon(draw, size, [(0.51, 0.35), (0.62, 0.37), (0.66, 0.83), (0.57, 0.91), (0.49, 0.82)], PIXEL_DARK)
    _polygon(draw, size, [(0.04, 0.49), (0.50, 0.49), (0.48, 0.84), (0.28, 0.94), (0.08, 0.72)], PIXEL_SHADOW)
    _polygon(draw, size, [(0.62, 0.49), (0.97, 0.48), (0.99, 0.72), (0.82, 0.91), (0.66, 0.84)], PIXEL_DARK)
    _line(draw, size, [(0.08, 0.73), (0.48, 0.84), (0.57, 0.92), (0.66, 0.84), (0.96, 0.72)], PIXEL_EDGE)
    _polygon(draw, size, [(0.34, 0.88), (0.74, 0.86), (0.70, 0.97), (0.57, 1.00), (0.39, 0.96)], PIXEL_SHADOW)
    _meteor_texture(image, 3)
    return image


def _draw_profile(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outer = [
        (0.12, 0.13), (0.38, 0.00), (0.70, 0.05), (0.86, 0.20),
        (0.88, 0.33), (1.00, 0.36), (1.00, 0.53), (0.88, 0.57),
        (0.85, 0.79), (0.67, 0.94), (0.43, 1.00), (0.17, 0.88),
        (0.02, 0.63), (0.00, 0.30),
    ]
    _polygon(draw, size, outer, PIXEL_MID)
    _polygon(draw, size, [(0.12, 0.13), (0.38, 0.00), (0.57, 0.03), (0.53, 0.37), (0.02, 0.37)], PIXEL_DARK)
    _polygon(draw, size, [(0.57, 0.03), (0.70, 0.05), (0.86, 0.20), (0.88, 0.33), (0.53, 0.37)], PIXEL_SHADOW)
    _line(draw, size, [(0.57, 0.04), (0.53, 0.37)], PIXEL_EDGE)
    _polygon(draw, size, [(0.04, 0.36), (0.98, 0.36), (1.00, 0.49), (0.05, 0.49)], PIXEL_DARK)
    _polygon(draw, size, [(0.58, 0.42), (0.96, 0.42), (0.96, 0.50), (0.58, 0.50)], PIXEL_CAVITY, None)
    _polygon(draw, size, [(0.60, 0.50), (0.91, 0.52), (0.85, 0.79), (0.67, 0.93), (0.58, 0.82)], PIXEL_SHADOW)
    _polygon(draw, size, [(0.04, 0.50), (0.57, 0.50), (0.56, 0.83), (0.43, 0.95), (0.18, 0.86), (0.04, 0.63)], PIXEL_DARK)
    _line(draw, size, [(0.56, 0.51), (0.56, 0.83), (0.67, 0.93)], PIXEL_EDGE)
    _polygon(draw, size, [(0.37, 0.88), (0.70, 0.85), (0.67, 0.94), (0.43, 1.00)], PIXEL_SHADOW)
    _meteor_texture(image, 2)
    return image


def _draw_back_three_quarter(size: tuple[int, int]) -> Image.Image:
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    outer = [
        (0.20, 0.06), (0.56, 0.00), (0.82, 0.11), (0.96, 0.33),
        (0.98, 0.74), (0.78, 0.92), (0.54, 1.00), (0.27, 0.94),
        (0.08, 0.75), (0.00, 0.34),
    ]
    _polygon(draw, size, outer, PIXEL_MID)
    _polygon(draw, size, [(0.20, 0.06), (0.56, 0.00), (0.53, 0.42), (0.03, 0.42)], PIXEL_DARK)
    _polygon(draw, size, [(0.56, 0.00), (0.82, 0.11), (0.96, 0.33), (0.95, 0.42), (0.53, 0.42)], PIXEL_SHADOW)
    _line(draw, size, [(0.56, 0.02), (0.53, 0.42)], PIXEL_EDGE)
    _polygon(draw, size, [(0.03, 0.42), (0.95, 0.42), (0.96, 0.56), (0.04, 0.56)], PIXEL_DARK)
    _polygon(draw, size, [(0.05, 0.57), (0.53, 0.57), (0.52, 0.87), (0.28, 0.94), (0.10, 0.75)], PIXEL_SHADOW)
    _polygon(draw, size, [(0.55, 0.57), (0.96, 0.57), (0.98, 0.74), (0.78, 0.92), (0.58, 0.86)], PIXEL_DARK)
    _line(draw, size, [(0.53, 0.57), (0.53, 0.87), (0.65, 0.95)], PIXEL_EDGE)
    _polygon(draw, size, [(0.33, 0.88), (0.72, 0.86), (0.68, 0.97), (0.54, 1.00), (0.39, 0.96)], PIXEL_SHADOW)
    _meteor_texture(image, 1)
    return image


def quantize_matte_black_iron(image: Image.Image) -> Image.Image:
    """Reduce the orthographic render to a neutral four-tone matte iron palette."""
    image = image.convert("RGBA")
    alpha = image.getchannel("A")
    opaque_values = []
    for red, green, blue, opacity in image.getdata():
        if opacity >= 128:
            opaque_values.append(red * 0.2126 + green * 0.7152 + blue * 0.0722)
    if not opaque_values:
        raise ValueError("Cannot quantize an empty helmet render")
    ordered = sorted(opaque_values)
    thresholds = [
        ordered[round((len(ordered) - 1) * fraction)]
        for fraction in (0.12, 0.30, 0.50, 0.70, 0.88)
    ]
    result = Image.new("RGBA", image.size, (0, 0, 0, 0))
    source = image.load()
    target = result.load()
    for y in range(image.height):
        for x in range(image.width):
            red, green, blue, opacity = source[x, y]
            if opacity < 128:
                continue
            luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
            palette_index = sum(luminance > threshold for threshold in thresholds)
            boundary = any(
                x + dx < 0
                or x + dx >= image.width
                or y + dy < 0
                or y + dy >= image.height
                or alpha.getpixel((x + dx, y + dy)) < 128
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1))
            )
            target[x, y] = MATTE_PALETTE[0 if boundary else palette_index]
    return result


def _direct_design_cutouts() -> dict[str, Image.Image]:
    """Remove the grey backdrop and key every source slot by its visible facing."""
    concept = Image.open(APPROVED_CONCEPT).convert("RGB")
    concept_width, concept_height = concept.size
    cutouts: dict[str, Image.Image] = {}
    DIRECT_DESIGN_ROOT.mkdir(parents=True, exist_ok=True)
    for source_slot, direction in enumerate(APPROVED_SOURCE_SLOT_DIRECTIONS):
        left = round(source_slot * concept_width / 8)
        right = round((source_slot + 1) * concept_width / 8)
        slot = concept.crop((left, 0, right, concept_height))
        border_pixels = []
        for y in range(slot.height):
            for x in range(min(8, slot.width)):
                border_pixels.append(slot.getpixel((x, y)))
                border_pixels.append(slot.getpixel((slot.width - 1 - x, y)))
        background = tuple(round(statistics.median(pixel[channel] for pixel in border_pixels)) for channel in range(3))
        mask = Image.new("L", slot.size, 0)
        mask_pixels = mask.load()
        slot_pixels = slot.load()
        for y in range(slot.height):
            for x in range(slot.width):
                difference = max(abs(slot_pixels[x, y][channel] - background[channel]) for channel in range(3))
                if difference > 7:
                    mask_pixels[x, y] = 255
        box = mask.getbbox()
        if box is None:
            raise ValueError(
                f"Approved concept source slot is empty after background removal: "
                f"slot={source_slot} direction={direction}"
            )
        rgb_crop = slot.crop(box)
        alpha_crop = mask.crop(box)
        cutout = rgb_crop.convert("RGBA")
        cutout.putalpha(alpha_crop)
        cutout.save(DIRECT_DESIGN_ROOT / f"approved_direct_{direction.lower()}.png")
        cutouts[direction] = cutout
    return cutouts


def effective_opaque_pixels(image: Image.Image) -> float:
    """Return alpha-weighted visible area in fully opaque pixel equivalents."""
    histogram = image.getchannel("A").histogram()
    return sum(alpha * count for alpha, count in enumerate(histogram)) / 255.0


def build_direction_variants(client_baseline: dict) -> list[Image.Image]:
    """Use the approved views directly and calibrate both envelope and visual mass."""
    runtime_envelopes: dict = client_baseline.get("directionRuntimeTargetSize", {})
    runtime_opaque_pixels: dict = client_baseline.get("directionRuntimeOpaquePixels", {})
    cutouts = _direct_design_cutouts()
    variants: list[Image.Image] = []
    for direction in CANONICAL_DIRECTIONS:
        cutout = cutouts[direction]
        envelope = runtime_envelopes.get(direction)
        if not isinstance(envelope, list) or len(envelope) != 2:
            raise ValueError(f"Missing real-client helmet envelope for {direction}")
        median_opaque_pixels = runtime_opaque_pixels.get(direction)
        if not isinstance(median_opaque_pixels, (int, float)) or median_opaque_pixels <= 0:
            raise ValueError(f"Missing real-client helmet visual mass for {direction}")
        maximum_width, maximum_height = int(envelope[0]), int(envelope[1])
        maximum_scale = min(maximum_width / cutout.width, maximum_height / cutout.height)
        target_visual_mass = float(median_opaque_pixels) * VISUAL_MASS_TARGET_MULTIPLIER
        candidates: dict[tuple[int, int], tuple[Image.Image, float]] = {}
        for step in range(1, 2001):
            scale = maximum_scale * step / 2000.0
            target_size = (
                max(1, round(cutout.width * scale)),
                max(1, round(cutout.height * scale)),
            )
            if target_size in candidates:
                continue
            candidate = cutout.resize(target_size, Image.Resampling.LANCZOS)
            candidates[target_size] = (candidate, effective_opaque_pixels(candidate))
        variant, _mass = min(
            candidates.values(),
            key=lambda record: (
                abs(math.log(max(record[1], 0.001) / target_visual_mass)),
                -record[1],
            ),
        )
        variants.append(variant)
    if any(image.getchannel("A").getbbox() is None for image in variants):
        raise AssertionError("Direct approved Black Iron Helmet direction is empty")
    return variants


def load_death_variants() -> list[list[Image.Image]]:
    labels = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]
    variants: list[list[Image.Image]] = []
    for label in labels:
        row: list[Image.Image] = []
        for frame in range(4):
            path = GODOT_RENDER_ROOT / f"death_{label}_f{frame}.png"
            image = Image.open(path).convert("RGBA")
            if image.getchannel("A").getbbox() is None:
                raise ValueError(f"Godot death pose is empty: {label} F{frame}")
            row.append(quantize_matte_black_iron(image))
        variants.append(row)
    return variants


def render_direction_reference(variants: list[Image.Image]) -> Path:
    labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    tile = (88, 92)
    sheet = Image.new("RGBA", (tile[0] * 8, 128), (14, 15, 18, 255))
    draw = ImageDraw.Draw(sheet)
    draw.text((6, 6), "Black Iron Helmet: approved narrow-jaw 8-direction family", fill=(235, 235, 235, 255))
    for direction, variant in enumerate(variants):
        enlarged = variant.resize((variant.width * 3, variant.height * 3), Image.Resampling.NEAREST)
        x = direction * tile[0] + (tile[0] - enlarged.width) // 2
        sheet.alpha_composite(enlarged, (x, 31))
        draw.text((direction * tile[0] + 5, 108), labels[direction], fill=(255, 218, 84, 255))
    target = ROOT / "outputs/visual_acceptance/black_iron_helmet_directions.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(target)
    return target


def anchor_bbox(data: bytes, palette: list, offsets: list[int], index: int) -> tuple[int, int, int, int]:
    image, meta = decode_sprite(data, offsets[index], palette)
    cell = Image.new("RGBA", CELL, (0, 0, 0, 0))
    cell.alpha_composite(
        image.convert("RGBA"),
        (SOURCE_DRAW_ORIGIN[0] + int(meta["x"]), SOURCE_DRAW_ORIGIN[1] + int(meta["y"])),
    )
    box = cell.getchannel("A").getbbox()
    if not box:
        raise ValueError(f"Anchor source frame {index} is empty")
    return box


def build_action(
    data: bytes,
    palette: list,
    offsets: list[int],
    variants: list[Image.Image],
    death_variants: list[list[Image.Image]],
    death_pose_records: dict[tuple[int, int], dict],
    pose_anchor_records: dict[tuple[str, int, int], dict],
    action_name: str,
) -> dict:
    spec = ACTIONS[action_name]
    frame_count = int(spec["frames"])
    atlas = Image.new("RGBA", (CELL[0] * frame_count, CELL[1] * 8), (0, 0, 0, 0))
    frames: list[dict] = []
    for direction in range(8):
        for frame in range(frame_count):
            within_appearance = int(spec["start"]) + direction * 8 + frame
            index = ANCHOR_APPEARANCE * ANCHOR_STRIDE + within_appearance
            box = anchor_bbox(data, palette, offsets, index)
            helmet = variants[direction]
            pose_variant = "approved-design-direct-resize"
            pose_record: dict | None = None
            if action_name == "death":
                helmet = death_variants[direction][frame]
                pose_record = death_pose_records[(direction, frame)]
                pose_variant = "godot-orthographic-complete-helmet"
            rotated = False
            anchor_record = pose_anchor_records[(action_name, direction, frame)]
            helmet_centroid = anchor_record["centroidMedian"]
            anchor_center_x = round(float(helmet_centroid[0]))
            anchor_center_y = round(float(helmet_centroid[1]))
            paste_x = frame * CELL[0] + anchor_center_x - helmet.width // 2
            paste_y_local = anchor_center_y - helmet.height // 2
            paste_y = direction * CELL[1] + paste_y_local
            atlas.alpha_composite(helmet, (paste_x, paste_y))
            frames.append(
                {
                    "anchorSourceIndex": index,
                    "direction": direction,
                    "frame": frame,
                    "anchorOpaqueBox": list(box),
                    "helmetAnchorCentroid": [anchor_center_x, anchor_center_y],
                    "helmetAnchorRule": "same-cell Hair.wil head-proximal Helmet.wil centroid cluster",
                    "hairAnchorCentroid": anchor_record["hairAnchorCentroid"],
                    "selectedAnchorAppearances": anchor_record["selectedAppearances"],
                    "rejectedAnchorAppearances": anchor_record["outlierAppearances"],
                    "paste": [paste_x - frame * CELL[0], paste_y - direction * CELL[1]],
                    "generatedSize": [helmet.width, helmet.height],
                    "rotatedForDeath": rotated,
                    "poseVariant": pose_variant,
                }
            )
    direction_signatures = [
        hashlib.sha256(
            atlas.crop((0, direction * CELL[1], atlas.width, (direction + 1) * CELL[1])).tobytes()
        ).hexdigest()
        for direction in range(8)
    ]
    if len(set(direction_signatures)) < 8:
        raise AssertionError(f"{action_name} does not contain eight distinct direction rows")
    target = OUTPUT / f"black_iron_helmet_{action_name}.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        accepted = Image.open(target).convert("RGBA")
        if accepted.size != atlas.size or accepted.tobytes() != atlas.tobytes():
            raise AssertionError(
                f"Accepted Black Iron Helmet atlas changed: {target.name}"
            )
    else:
        atlas.save(target)
    return {
        "path": f"res://{target.relative_to(ROOT).as_posix()}",
        "sha256": sha256(target),
        "cell": list(CELL),
        "directions": 8,
        "framesPerDirection": frame_count,
        "frames": frames,
        "directionSignatures": direction_signatures,
    }


def main() -> None:
    for required in (
        REFERENCE_ICON,
        APPROVED_CONCEPT,
        GODOT_RENDER_MANIFEST,
        DEATH_POSE_BASELINE,
        CLIENT_HELMET_BASELINE,
        ANCHOR_SOURCE,
        SOURCE_CODE,
        FRAME_CODE,
        COMPLETE_SCAN,
    ):
        if not required.exists():
            raise FileNotFoundError(f"Missing Black Iron Helmet evidence: {required}")
    scan = json.loads(COMPLETE_SCAN.read_text(encoding="utf-8"))
    client_helmet_baseline = json.loads(CLIENT_HELMET_BASELINE.read_text(encoding="utf-8"))
    death_pose_baseline = json.loads(DEATH_POSE_BASELINE.read_text(encoding="utf-8"))
    godot_render_manifest = json.loads(GODOT_RENDER_MANIFEST.read_text(encoding="utf-8"))
    if scan.get("libraryCount") != 122 or scan.get("indexedFramesScanned") != 962251:
        raise AssertionError("Complete-client scan is not complete")
    variants = build_direction_variants(client_helmet_baseline)
    death_variants = load_death_variants()
    death_pose_records = {
        (int(record["directionRow"]), int(record["frame"])): record
        for record in death_pose_baseline.get("records", [])
    }
    pose_anchor_records = {
        (action_name, int(record["directionRow"]), int(record["frame"])): record
        for action_name, records in client_helmet_baseline.get("poseAnchors", {}).items()
        for record in records
    }
    expected_anchor_records = sum(8 * int(spec["frames"]) for spec in ACTIONS.values())
    if len(pose_anchor_records) != expected_anchor_records:
        raise AssertionError(
            f"Helmet.wil same-cell anchor table is incomplete: {len(pose_anchor_records)} != {expected_anchor_records}"
        )
    if len(death_pose_records) != 32 or len(godot_render_manifest.get("records", [])) != 32:
        raise AssertionError("Godot death pipeline does not contain the complete 8x4 mapping")
    direction_reference = render_direction_reference(variants)
    data, palette, offsets, info = read_library(ANCHOR_SOURCE)
    actions = {
        name: build_action(
            data,
            palette,
            offsets,
            variants,
            death_variants,
            death_pose_records,
            pose_anchor_records,
            name,
        )
        for name in ACTIONS
    }
    payload = {
        "schemaVersion": 16,
        "item": "Black Iron Helmet / 黑铁头盔",
        "classification": "project-generated presentation asset based on verified classic evidence",
        "referenceIcon": f"res://{REFERENCE_ICON.relative_to(ROOT).as_posix()}",
        "referenceIconSha256": sha256(REFERENCE_ICON),
        "referenceIconImage": 344,
        "approvedDirectionReferences": {
            "approvedConcept": f"res://{APPROVED_CONCEPT.relative_to(ROOT).as_posix()}",
            "approvedConceptSha256": sha256(APPROVED_CONCEPT),
            "directDirectionCutouts": f"res://{DIRECT_DESIGN_ROOT.relative_to(ROOT).as_posix()}",
            "directUsePolicy": "The eight approved views are used directly; processing is limited to grey-background removal and aspect-preserving resize.",
            "sourceSlotDirectionOrder": APPROVED_SOURCE_SLOT_DIRECTIONS,
            "canonicalRowSourceSlots": CANONICAL_ROW_SOURCE_SLOTS,
            "godotRenderer": "res://tools/render_black_iron_helmet_3d.gd",
            "godotRendererSha256": sha256(ROOT / "tools/render_black_iron_helmet_3d.gd"),
            "godotRenderManifest": f"res://{GODOT_RENDER_MANIFEST.relative_to(ROOT).as_posix()}",
            "godotRenderManifestSha256": sha256(GODOT_RENDER_MANIFEST),
            "acceptedRowMapping": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"],
        },
        "anchorLibrary": f"res://{ANCHOR_SOURCE.relative_to(ROOT).as_posix()}",
        "anchorLibraryImageCount": int(info["image_count"]),
        "anchorAppearance": ANCHOR_APPEARANCE,
        "anchorStride": ANCHOR_STRIDE,
        "anchorUsage": "same-cell position/motion and death-facing calibration only; no anchor-source pixels copied",
        "completeClientScan": f"res://{COMPLETE_SCAN.relative_to(ROOT).as_posix()}",
        "completeClientCoverage": {
            "libraries": scan["libraryCount"],
            "indexedFrames": scan["indexedFramesScanned"],
            "validFrames": scan["validFrames"],
        },
        "clientHelmetParameterBaseline": {
            "path": f"res://{CLIENT_HELMET_BASELINE.relative_to(ROOT).as_posix()}",
            "sha256": sha256(CLIENT_HELMET_BASELINE),
            "directionRuntimeMaxSize": client_helmet_baseline["directionRuntimeMaxSize"],
            "directionRuntimeTargetSize": client_helmet_baseline["directionRuntimeTargetSize"],
            "directionRuntimeOpaquePixels": client_helmet_baseline["directionRuntimeOpaquePixels"],
            "poseAnchorRule": client_helmet_baseline["poseAnchorRule"],
            "poseAnchorRecords": len(pose_anchor_records),
            "outlierFilteredPoseRecords": client_helmet_baseline["outlierFilteredPoseRecords"],
            "deathCanonicalRotate90Degrees": client_helmet_baseline["deathFinal"]["canonicalSpriteRotate90Degrees"],
        },
        "deathPoseBaseline": {
            "path": f"res://{DEATH_POSE_BASELINE.relative_to(ROOT).as_posix()}",
            "sha256": sha256(DEATH_POSE_BASELINE),
            "records": len(death_pose_records),
            "mappingRule": death_pose_baseline["mappingRule"],
            "rendererPolicy": death_pose_baseline["rendererPolicy"],
        },
        "sourceEvidence": {
            "runtimeHeadLibrary": f"res://{SOURCE_CODE.relative_to(ROOT).as_posix()}",
            "runtimeFinding": "DrawHead uses HairLibrary; no equipped-helmet mapping exists in the paired runtime.",
            "actionFrames": f"res://{FRAME_CODE.relative_to(ROOT).as_posix()}",
            "rejectedHairLook2": "Narrow hair strip; visually rejected and used only as a motion anchor.",
            "rejectedHelmetWil": "Six horned/open-face families; none matches StateItem #344.",
        },
        "generation": {
            "equipmentIcon": "Verified StateItem #344 remains the equipment-window icon and unique identity evidence; its old derived world pixels are not used.",
            "runtimeDirections": "The approved source slots are visually classified as N/E/W/SW/S/SE/NW/NE, then reordered through source slots 0/7/1/5/4/3/2/6 into canonical game rows N/NE/E/SE/S/SW/W/NW; only the grey backdrop is removed and each crop is resized with its aspect ratio preserved.",
            "deathDirections": "Every N/NE/E/SE/S/SW/W/NW x F0/F1/F2/F3 cell is independently rendered from the same-row same-frame evidence record.",
            "authorship": "Project-generated extension; not claimed as an original client world frame.",
            "aiGenerated": True,
            "aiConceptUsed": True,
            "aiPixelsLimitedTo": ["idle", "walk", "attack", "cast", "hit"],
            "runtimePixelGenerator": "Direct approved-design crops with background removal and aspect-preserving resize for standing/action directions; Godot 4.7 orthographic complete-geometry renderer for death poses.",
            "oldDerivedStateItemWorldPixelsUsed": False,
            "scalePolicy": "Choose the aspect-preserving size that stays inside the same-direction client median envelope and most closely matches 1.15x its alpha-weighted visible-area median; no redraw, recolour or quantization.",
            "visualMassTargetMultiplier": VISUAL_MASS_TARGET_MULTIPLIER,
            "runtimeEnvelopeScale": RUNTIME_ENVELOPE_SCALE,
            "positionPolicy": "For every action/direction/frame, reject any separated Helmet.wil centroid cluster that is far from the same-cell male-warrior Hair.wil head, then centre the generated sprite on the median of the remaining head-proximal samples.",
            "deathPosePolicy": "Use the exact same direction row and frame column in warrior_death.png, Helmet.wil and Hair.wil; render the complete helmet geometry, then centre it on the same-cell head-proximal Helmet.wil cluster.",
        },
        "directionReference": f"res://{direction_reference.relative_to(ROOT).as_posix()}",
        "actions": actions,
        "policy": "Complete-client evidence first; generated art is explicitly separated from original client assets.",
    }
    PROVENANCE.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "BLACK_IRON_HELMET_GENERATED_PASS "
        "runtime_reference=approved_design_direct_resize death_reference=godot_orthographic_complete_geometry "
        "actions=6 directions=8 death_pose_records=32 old_stateitem_world_pixels=0 anchor_pixels_copied=0"
    )


if __name__ == "__main__":
    main()
