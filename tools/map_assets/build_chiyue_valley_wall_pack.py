#!/usr/bin/env python3
"""Build the natural Chiyue Valley cave-rock wall family.

The pack deliberately reuses the reviewed Wooma/Orc wall slot contract:
16 straight modules on the native 64x32 isometric grid (X/Y, lengths
1/2/3x3/4x3), with 160px wall faces and no corner assets.  Only the tracked
ImageGen source art changes the look; geometry and placement remain canonical.
"""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
from collections import Counter

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE_FAMILY_ID = "orc_tomb_rough_stone_u0"
SOURCE_PREFIX = "orc_tomb_wall_"
FAMILY_ID = "chiyue_valley_rock_wall_u0"
SOCKET_ID = "chiyue_valley_rock_wall_socket_u0"
TARGET_PREFIX = "chiyue_valley_wall_"
VISUAL_PROFILE_ID = "chiyue_valley_native_2to1_rock_wall_v1"
PROJECTION_CONTRACT_ID = "isometric_cell_64x32_exact_v1"
PLACEMENT_CONTRACT_ID = "wall_foot_on_cell_edge_64x32_v1"
IMAGEGEN_SESSION_ID = "01a01ede-3674-7e13-9da2-95fcf6ab1745"
GENERATED_IMAGE_ROOT = (
    Path(r"C:\Users\Administrator\.codex\generated_images")
    / IMAGEGEN_SESSION_ID
)
FRONT_BASE_OUTPUT_ID = "exec-a16c2c00-468a-45e3-a09e-35e7b6b63dda.png"
FRONT_BASE_RAW_SHA256 = "494e6d6e7af9c8927747b4d2978e6c4a6132a4e423ee996024d652b575a15573"
FRONT_CROP_BOXES = (
    (60, 120, 210, 870),
    (250, 260, 400, 1010),
    (470, 520, 620, 1270),
    (660, 760, 810, 1510),
)
FRONT_SPECS = tuple(
    {
        "variant": index + 1,
        "output_id": FRONT_BASE_OUTPUT_ID,
        "raw_sha256": FRONT_BASE_RAW_SHA256,
        "tracked_name": f"chiyue_valley_wall_front_v{index + 1:02d}.png",
        "crop_box_in_raw_source": list(box),
    }
    for index, box in enumerate(FRONT_CROP_BOXES)
)
CAP_OUTPUT_ID = "exec-394b3c43-bf78-40ad-9aaa-d97b8e17af26.png"
CAP_BASE_RAW_SHA256 = "986043f92428b62b3c7fd2256620049814a359d88e535cd9cb25744eec3759d9"
CAP_CROP_SIZE = 896
CAP_CROP_BOXES = (
    (0, 0, CAP_CROP_SIZE, CAP_CROP_SIZE),
    (1194 - CAP_CROP_SIZE, 0, 1194, CAP_CROP_SIZE),
    (0, 1198 - CAP_CROP_SIZE, CAP_CROP_SIZE, 1198),
    (1194 - CAP_CROP_SIZE, 1198 - CAP_CROP_SIZE, 1194, 1198),
)
CAP_SPECS = tuple(
    {
        "variant": index + 1,
        "tracked_name": f"chiyue_valley_wall_cap_v{index + 1:02d}.png",
        "crop_box_in_dominant_alpha": list(box),
    }
    for index, box in enumerate(CAP_CROP_BOXES)
)

# Each tile consumes one front and one cap texture.  The layouts are fixed,
# deterministic, and deliberately differ between X/Y so long walls do not
# repeat one source image.  Adjacent tiles never reuse either source index.
SOURCE_VARIANT_LAYOUTS = {
    ("iso_x", 1, 1): ((1, 1),),
    ("iso_x", 2, 1): ((2, 3), (3, 4)),
    ("iso_x", 3, 1): ((1, 2), (2, 3), (3, 4)),
    ("iso_x", 3, 2): ((4, 1), (3, 2), (2, 4)),
    ("iso_x", 3, 3): ((3, 4), (1, 2), (4, 3)),
    ("iso_x", 4, 1): ((1, 2), (2, 3), (3, 4), (4, 1)),
    ("iso_x", 4, 2): ((2, 4), (4, 1), (1, 3), (3, 2)),
    ("iso_x", 4, 3): ((3, 1), (1, 4), (4, 2), (2, 3)),
    ("iso_y", 1, 1): ((4, 4),),
    ("iso_y", 2, 1): ((1, 3), (4, 2)),
    ("iso_y", 3, 1): ((2, 1), (4, 3), (1, 4)),
    ("iso_y", 3, 2): ((3, 2), (2, 4), (4, 1)),
    ("iso_y", 3, 3): ((1, 4), (3, 1), (2, 3)),
    ("iso_y", 4, 1): ((4, 3), (3, 1), (1, 2), (2, 4)),
    ("iso_y", 4, 2): ((1, 2), (3, 4), (2, 1), (4, 3)),
    ("iso_y", 4, 3): ((2, 3), (1, 4), (4, 2), (3, 1)),
}
LEGACY_SOURCE_NAMES = (
    "chiyue_valley_wall_front_source.png",
    "chiyue_valley_wall_cap_source.png",
)

ART_ROOT = (
    ROOT
    / "assets"
    / "art"
    / "maps"
    / "_shared"
    / "walls"
    / "chiyue_valley"
    / FAMILY_ID
)
TRACKED_SOURCE_DIR = ART_ROOT.parent / "source"
PROVENANCE_PATH = TRACKED_SOURCE_DIR / "chiyue_valley_wall_source_provenance.json"
SOURCE_EXTERNAL_PATH = "assets/art/maps/_shared/walls/chiyue_valley/source"
PREVIEW_PATH = TRACKED_SOURCE_DIR / "chiyue_valley_wall_pack_contact_sheet.png"

MODULE_CATALOG = ROOT / "assets" / "data" / "assets" / "wall_module_catalog.json"
FAMILY_CATALOG = ROOT / "assets" / "data" / "assets" / "wall_family_catalog.json"
ASSET_CATALOG = (
    ROOT
    / "assets"
    / "data"
    / "assets"
    / "map_chiyue_valley_wall_asset_catalog.json"
)

GRID_TILE = (64, 32)
FACE_SIZE = (32, 160)
SEGMENT_SIZE = (96, 224)
ANCHOR_Y = 184
RESAMPLE = Image.Resampling.LANCZOS
FACE_RESAMPLE = Image.Resampling.BILINEAR
EXPECTED_SELECTION_BOUNDS = {
    ("iso_x", 1): [32, 8, 63, 191],
    ("iso_x", 2): [32, 8, 95, 207],
    ("iso_x", 3): [32, 8, 127, 223],
    ("iso_x", 4): [32, 8, 159, 239],
    ("iso_y", 1): [1, 8, 63, 191],
    ("iso_y", 2): [1, 8, 95, 207],
    ("iso_y", 3): [1, 8, 127, 223],
    ("iso_y", 4): [1, 8, 159, 239],
}

CAP_EXTERNAL_PATH = str(GENERATED_IMAGE_ROOT / CAP_OUTPUT_ID)
CLIPBOARD_REFERENCE_PATH = (
    r"C:\Users\ADMINI~1\AppData\Local\Temp"
    r"\codex-clipboard-1d2451a7-b6dc-40ee-b56d-bb810caa5876.png"
)
CLIPBOARD_REFERENCE_SHA256 = (
    "382e3c0c87f44a0270e2bd9e399b88cebe75cf36d76fe65dd38359e112b23ffe"
)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _image_metadata(path: Path) -> dict:
    with Image.open(path) as opened:
        rgba = opened.convert("RGBA")
        alpha = rgba.getchannel("A")
        return {
            "tracked_path": path.relative_to(ROOT).as_posix(),
            "sha256": sha256(path),
            "dimensions": list(rgba.size),
            "mode": opened.mode,
            "alpha_extrema": list(alpha.getextrema()),
        }


def dominant_alpha_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    """Trim to the dominant alpha silhouette before texture projection.

    The reviewed front source has a few isolated one-pixel alpha specks far
    outside its connected wall silhouette.  A raw Image.getbbox() keeps those
    specks and compresses the actual rock face into a narrow strip.  Use a
    deterministic scanline occupancy threshold to recover the meaningful
    alpha bounding box without changing any source pixels inside it.
    """
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A")
    width, height = rgba.size
    column_threshold = max(2, int(round(height * 0.0025)))
    row_threshold = max(2, int(round(width * 0.0025)))
    columns = [
        x
        for x in range(width)
        if sum(alpha.getpixel((x, y)) > 0 for y in range(height))
        >= column_threshold
    ]
    rows = [
        y
        for y in range(height)
        if sum(alpha.getpixel((x, y)) > 0 for x in range(width))
        >= row_threshold
    ]
    if not columns or not rows:
        raise RuntimeError("source image has no visible pixels")
    return (min(columns), min(rows), max(columns) + 1, max(rows) + 1)


def alpha_trim(image: Image.Image) -> Image.Image:
    box = dominant_alpha_bbox(image)
    rgba = image.convert("RGBA")
    trimmed = rgba.crop(box)
    if trimmed.getchannel("A").getbbox() is None:
        raise RuntimeError("source image dominant alpha bbox has no visible pixels")
    return trimmed


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def _external_path(output_id: str) -> Path:
    return GENERATED_IMAGE_ROOT / output_id


def _verify_external_sha(path: Path, expected: str) -> str:
    if not path.is_file():
        raise RuntimeError(f"missing reviewed ImageGen source: {path}")
    actual = sha256(path)
    if actual != expected:
        raise RuntimeError(f"source SHA256 changed for {path.name}: {actual} != {expected}")
    return actual


def _assert_real_alpha(image: Image.Image, path: Path) -> None:
    extrema = image.convert("RGBA").getchannel("A").getextrema()
    if extrema != (0, 255):
        raise RuntimeError(f"{path} must have real alpha (0..255), got {extrema}")


def prepare_tracked_sources() -> tuple[dict[int, Image.Image], dict[int, Image.Image], list[dict]]:
    """Materialize exactly four front and four cap sources under source/."""
    TRACKED_SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    for legacy_name in LEGACY_SOURCE_NAMES:
        legacy_path = TRACKED_SOURCE_DIR / legacy_name
        if legacy_path.is_file():
            legacy_path.unlink()

    front_sources: dict[int, Image.Image] = {}
    provenance_sources: list[dict] = []
    front_raw_path = _external_path(FRONT_BASE_OUTPUT_ID)
    front_raw_sha256 = _verify_external_sha(front_raw_path, FRONT_BASE_RAW_SHA256)
    with Image.open(front_raw_path) as opened:
        front_raw = opened.convert("RGBA")
    if front_raw.getchannel("A").getextrema() != (255, 255):
        raise RuntimeError("hard planar FRONT_BASE must be an opaque source")
    for spec in FRONT_SPECS:
        crop_box = tuple(int(value) for value in spec["crop_box_in_raw_source"])
        if crop_box[2] - crop_box[0] != 150 or crop_box[3] - crop_box[1] != 750:
            raise RuntimeError(f"front crop must be 1:5 (150x750): {crop_box}")
        if not (
            0 <= crop_box[0] < crop_box[2] <= front_raw.width
            and 0 <= crop_box[1] < crop_box[3] <= front_raw.height
        ):
            raise RuntimeError(f"front crop outside FRONT_BASE: {crop_box}")
        crop = front_raw.crop(crop_box)
        # These windows are deliberately inside the hard-rock body.  Reject
        # any near-white pixel so a background fringe cannot enter the pack.
        if any(
            min(pixel) >= 245 and max(pixel) - min(pixel) <= 12
            for pixel in crop.convert("RGB").getdata()
        ):
            raise RuntimeError(f"front crop includes pale background: {crop_box}")
        crop.putalpha(Image.new("L", crop.size, 255))
        tracked_path = TRACKED_SOURCE_DIR / str(spec["tracked_name"])
        save_png(crop, tracked_path)
        with Image.open(tracked_path) as opened:
            tracked = opened.convert("RGBA")
        if tracked.getchannel("A").getextrema() != (255, 255):
            raise RuntimeError(f"front crop lost opaque alpha: {tracked_path}")
        front_sources[int(spec["variant"])] = tracked
        provenance_sources.append(
            {
                "role": "front",
                "variant": int(spec["variant"]),
                "tracked_path": res_path(tracked_path),
                "raw_external_path": str(front_raw_path),
                "raw_output_id": FRONT_BASE_OUTPUT_ID,
                "raw_sha256": front_raw_sha256,
                "tracked_sha256": sha256(tracked_path),
                "crop_box_in_raw_source": list(crop_box),
                "source_cleanup_policy": "internal_hard_planar_rock_crop_set_alpha_255",
                "style_contract": "hard_planar_wet_cave_rock_moss_confined_to_fissures",
                "raw_dimensions": list(front_raw.size),
                "raw_alpha_extrema": list(front_raw.getchannel("A").getextrema()),
                "dimensions": list(tracked.size),
                "mode": "RGBA",
                "alpha_extrema": list(tracked.getchannel("A").getextrema()),
            }
        )

    cap_raw_path = _external_path(CAP_OUTPUT_ID)
    cap_raw_sha256 = _verify_external_sha(cap_raw_path, CAP_BASE_RAW_SHA256)
    with Image.open(cap_raw_path) as opened:
        cap_raw = opened.convert("RGBA")
    _assert_real_alpha(cap_raw, cap_raw_path)
    cap_bbox = dominant_alpha_bbox(cap_raw)
    cap_dominant = cap_raw.crop(cap_bbox)
    if cap_dominant.size != (1194, 1198):
        raise RuntimeError(f"unexpected cap dominant crop size: {cap_dominant.size}")
    cap_sources: dict[int, Image.Image] = {}
    for spec in CAP_SPECS:
        crop_box = tuple(int(value) for value in spec["crop_box_in_dominant_alpha"])
        if crop_box[2] - crop_box[0] != CAP_CROP_SIZE or crop_box[3] - crop_box[1] != CAP_CROP_SIZE:
            raise RuntimeError(f"cap crop is not square: {crop_box}")
        derived = cap_dominant.crop(crop_box)
        tracked_path = TRACKED_SOURCE_DIR / str(spec["tracked_name"])
        save_png(derived, tracked_path)
        with Image.open(tracked_path) as opened:
            tracked = opened.convert("RGBA")
        _assert_real_alpha(tracked, tracked_path)
        cap_sources[int(spec["variant"])] = alpha_trim(tracked)
        raw_box = [
            cap_bbox[0] + crop_box[0],
            cap_bbox[1] + crop_box[1],
            cap_bbox[0] + crop_box[2],
            cap_bbox[1] + crop_box[3],
        ]
        provenance_sources.append(
            {
                "role": "cap",
                "variant": int(spec["variant"]),
                "tracked_path": res_path(tracked_path),
                "raw_external_path": str(cap_raw_path),
                "raw_output_id": CAP_OUTPUT_ID,
                "raw_sha256": cap_raw_sha256,
                "tracked_sha256": sha256(tracked_path),
                "dominant_alpha_bbox": list(cap_bbox),
                "crop_box_in_dominant_alpha": list(crop_box),
                "crop_box_in_raw_source": raw_box,
                "source_cleanup_policy": "dominant_alpha_bbox_then_deterministic_quadrant_crop",
                "style_contract": "hard_planar_wet_cave_rock_moss_confined_to_fissures",
                "dimensions": list(tracked.size),
                "mode": "RGBA",
                "alpha_extrema": list(tracked.getchannel("A").getextrema()),
            }
        )
    return front_sources, cap_sources, provenance_sources


def res_path(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def display_name(module: dict) -> str:
    axis_name = "X向" if module["axis"] == "iso_x" else "Y向"
    return (
        f"赤月洞穴岩壁 {axis_name} "
        f"{int(module['length_tiles'])}格 变体{int(module.get('variant', 1))}"
    )


def _opaque_texture(source: Image.Image) -> Image.Image:
    """Keep alpha-trimmed source edges from becoming black resize fringes."""
    rgba = source.convert("RGBA")
    rock_shadow = Image.new("RGBA", rgba.size, (34, 37, 25, 255))
    return Image.alpha_composite(rock_shadow, rgba)


def _project_capstone(source: Image.Image) -> Image.Image:
    """Map the cave-rock surface to the exact 64x32 isometric diamond."""
    square = _opaque_texture(source).resize((64, 64), RESAMPLE)
    projected = square.transform(
        (64, 32),
        Image.Transform.AFFINE,
        (1.0, 2.0, -32.0, -1.0, 2.0, 32.0),
        resample=Image.Resampling.BICUBIC,
    )
    mask = Image.new("L", (64, 32), 0)
    pixels = mask.load()
    for y in range(32):
        for x in range(64):
            if 0 < x < 63 and abs(x - 32) * 0.5 + abs(y - 16) <= 16.0:
                pixels[x, y] = 255
    # The canonical Wooma contract uses the complete cap diamond.  The source
    # remains alpha-trimmed, while the generated tile receives the exact mask
    # so all source variants share identical bounds and seams.
    projected.putalpha(mask)
    return projected


def _project_facade(source: Image.Image) -> Image.Image:
    """Map a flat 32x160 cave-rock bay to a +0.5 isometric wall face."""
    # Bilinear preserves the canonical 175px projected foot edge after the
    # after the internal hard-rock crop.  No brightness/color variant is
    # applied: every source window fills one complete 32x160 face.
    face = _opaque_texture(source).resize(FACE_SIZE, FACE_RESAMPLE)
    projected = Image.new("RGBA", (32, 176), (0, 0, 0, 0))
    for x in range(32):
        shift = x // 2
        projected.alpha_composite(face.crop((x, 0, x + 1, 160)), (x, shift))
    return projected


def native_segment(
    front_source: Image.Image,
    cap_source: Image.Image,
) -> Image.Image:
    """Create one canonical cell with matching cap/face seams."""
    segment = Image.new("RGBA", SEGMENT_SIZE, (0, 0, 0, 0))
    segment.alpha_composite(_project_facade(front_source), (32, 24))
    segment.alpha_composite(_project_capstone(cap_source), (32, 8))
    return segment


def split_continuous_parts(
    artwork: Image.Image,
    length: int,
    axis: str,
) -> list[Image.Image]:
    if length <= 1:
        return [artwork.copy()]
    alpha_box = artwork.getchannel("A").getbbox()
    if alpha_box is None:
        raise RuntimeError("wall artwork has no visible pixels")
    left, _top, right, _bottom = alpha_box
    width = max(1, right - left)
    parts = [
        Image.new("RGBA", artwork.size, (0, 0, 0, 0))
        for _index in range(length)
    ]
    for x in range(left, right):
        index = min(length - 1, int((x - left) * length / width))
        if axis == "iso_y":
            index = length - 1 - index
        parts[index].alpha_composite(
            artwork.crop((x, 0, x + 1, artwork.height)),
            (x, 0),
        )
    return parts


def _apply_native_geometry(module: dict) -> None:
    length = int(module["length_tiles"])
    axis = str(module["axis"])
    canvas_width = 32 * length + 64
    canvas_height = 208 + 16 * length
    module["canvas_size"] = [canvas_width, canvas_height]
    module["anchor"] = [
        64 if axis == "iso_x" else canvas_width - 64,
        ANCHOR_Y,
    ]
    seam_start_y = ANCHOR_Y
    if axis == "iso_x":
        module["start_seam_px"] = [32, seam_start_y]
        module["end_seam_px"] = [
            32 + 32 * length,
            seam_start_y + 16 * length,
        ]
    else:
        module["start_seam_px"] = [canvas_width - 32, seam_start_y]
        module["end_seam_px"] = [
            canvas_width - 32 - 32 * length,
            seam_start_y + 16 * length,
        ]


def straight_art(
    module: dict,
    front_sources: dict[int, Image.Image],
    cap_sources: dict[int, Image.Image],
) -> tuple[Image.Image, list[Image.Image], tuple[tuple[int, int], ...]]:
    length = int(module["length_tiles"])
    axis = str(module["axis"])
    size = tuple(int(value) for value in module["canvas_size"])
    layout = SOURCE_VARIANT_LAYOUTS[(axis, length, int(module.get("variant", 1)))]
    artwork = Image.new("RGBA", size, (0, 0, 0, 0))
    for tile_index, (front_variant, cap_variant) in enumerate(layout):
        segment = native_segment(
            front_sources[front_variant],
            cap_sources[cap_variant],
        )
        artwork.alpha_composite(segment, (32 * tile_index, 16 * tile_index))
    if axis == "iso_y":
        artwork = artwork.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        layout = tuple(reversed(layout))
    return artwork, split_continuous_parts(artwork, length, axis), layout


def build_module(
    source_module: dict,
    front_sources: dict[int, Image.Image],
    cap_sources: dict[int, Image.Image],
    provenance_sources: list[dict],
    clipboard_sha256: str | None,
) -> tuple[dict, dict]:
    module = copy.deepcopy(source_module)
    asset_id = str(module["asset_id"]).replace(SOURCE_PREFIX, TARGET_PREFIX, 1)
    module.update(
        {
            "asset_id": asset_id,
            "display_name": display_name(module),
            "category": "dungeon_wall",
            "theme": "chiyue_valley",
            "wall_family_id": FAMILY_ID,
            "socket_profile_id": SOCKET_ID,
            "content_layer": "personal_expansion",
            "collision_cells": [],
            "collision_footprint_tiles": [0, 0],
            "placement_clearance_cells": [],
            "collision_policy": "none",
            "navigation_policy": "ignore",
            "manual_collision_expected": True,
            "collision_authority": "manual_by_user",
            "collision_profile_id": "none_visual",
            "map_collision_override": "disabled",
            "calibration_status": "placeable",
            "placeable": True,
            "repeat_group": str(module.get("repeat_group", "")).replace(
                "orc_tomb_", "chiyue_valley_", 1
            ),
            "visual_profile_id": VISUAL_PROFILE_ID,
            "native_projection_contract_id": PROJECTION_CONTRACT_ID,
            "placement_contract_id": PLACEMENT_CONTRACT_ID,
            "corner_join_mode": "straight_overlap",
            "contains_corner_pillar": False,
            "wall_cap_thickness_tiles": 1,
            "wall_cap_projection_px": [32, 16],
        }
    )
    _apply_native_geometry(module)
    for connector in module.get("connectors", []):
        connector["socket_profile_id"] = SOCKET_ID

    layout = SOURCE_VARIANT_LAYOUTS[(
        str(module["axis"]),
        int(module["length_tiles"]),
        int(module.get("variant", 1)),
    )]
    for previous, current in zip(layout, layout[1:]):
        if previous[0] == current[0] or previous[1] == current[1]:
            raise RuntimeError(f"adjacent source reuse in {asset_id}: {layout}")
    artwork, parts, part_layout = straight_art(module, front_sources, cap_sources)
    asset_dir = ART_ROOT / asset_id
    asset_dir.mkdir(parents=True, exist_ok=True)
    composite_path = asset_dir / f"composite_{VISUAL_PROFILE_ID}.png"
    save_png(artwork, composite_path)

    source_by_key = {
        (str(entry["role"]), int(entry["variant"])): entry
        for entry in provenance_sources
    }
    render_parts: list[dict] = []
    for index, part_image in enumerate(parts):
        part_path = asset_dir / f"part_{index:02d}_{VISUAL_PROFILE_ID}_base.png"
        save_png(part_image, part_path)
        tile_offset = [index, 0] if module["axis"] == "iso_x" else [0, index]
        front_variant, cap_variant = part_layout[index]
        front_entry = source_by_key[("front", front_variant)]
        cap_entry = source_by_key[("cap", cap_variant)]
        render_parts.append(
            {
                "part_id": f"p{index:02d}",
                "tile_offset": tile_offset,
                "base_image": res_path(part_path),
                "front_image": "",
                "shadow_image": "",
                "anchor": list(module["anchor"]),
                "sort_tile_offset": tile_offset,
                "draw_order_index": index,
                "front_source_variant": front_variant,
                "cap_source_variant": cap_variant,
                "front_source_path": front_entry["tracked_path"],
                "cap_source_path": cap_entry["tracked_path"],
            }
        )
    module["render_mode"] = "single_part" if len(parts) == 1 else "segmented"
    module["render_parts"] = render_parts
    module["source_variant_layout"] = [
        {
            "front_source_variant": front_variant,
            "cap_source_variant": cap_variant,
        }
        for front_variant, cap_variant in part_layout
    ]

    alpha_bounds = artwork.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise RuntimeError(f"{asset_id} has no visible pixels")
    visible_bounds = [
        alpha_bounds[0],
        alpha_bounds[1],
        alpha_bounds[2] - alpha_bounds[0],
        alpha_bounds[3] - alpha_bounds[1],
    ]
    expected_bounds = EXPECTED_SELECTION_BOUNDS[(str(module["axis"]), int(module["length_tiles"]))]
    if visible_bounds != expected_bounds:
        raise RuntimeError(
            f"{asset_id} visible bounds {visible_bounds} != Wooma contract {expected_bounds}"
        )
    module["visible_bounds_px"] = visible_bounds
    module["selection_bounds_px"] = visible_bounds
    selected_front_hashes = [
        source_by_key[("front", front_variant)]["tracked_sha256"]
        for front_variant, _cap_variant in part_layout
    ]
    selected_cap_hashes = [
        source_by_key[("cap", cap_variant)]["tracked_sha256"]
        for _front_variant, cap_variant in part_layout
    ]
    front_sha256 = hashlib.sha256("|".join(selected_front_hashes).encode("utf-8")).hexdigest()
    cap_sha256 = hashlib.sha256("|".join(selected_cap_hashes).encode("utf-8")).hexdigest()
    source_tokens = []
    for front_variant, cap_variant in part_layout:
        source_tokens.append(
            ":".join(
                (
                    str(front_variant),
                    str(cap_variant),
                    source_by_key[("front", front_variant)]["tracked_sha256"],
                    source_by_key[("cap", cap_variant)]["tracked_sha256"],
                )
            )
        )
    combined_source_sha256 = hashlib.sha256(
        "|".join(source_tokens).encode("utf-8")
    ).hexdigest()
    digest = sha256(composite_path)
    all_front_output_ids = [FRONT_BASE_OUTPUT_ID]
    asset = {
        **copy.deepcopy(module),
        "asset_type": "wall_module",
        "category": "wall_module",
        "object_class": "wall",
        "image": res_path(composite_path),
        "thumbnail": res_path(composite_path),
        "image_size": list(artwork.size),
        "visible_bounds_px": visible_bounds,
        "selection_bounds_px": visible_bounds,
        "anchor_px": list(module["anchor"]),
        "placement_anchor_px": list(module["anchor"]),
        "anchor_tile": [0, 0],
        "anchor_mode": "foot_tile",
        "placement_preview_mode": "image_and_footprint",
        "visual_footprint_tiles": list(module["footprint_tiles"]),
        "occupancy_footprint_tiles": list(module["footprint_tiles"]),
        "base_footprint_tiles": list(module["footprint_tiles"]),
        "collision_footprint_tiles": [0, 0],
        "tile_size": list(GRID_TILE),
        "approved_scale": 1.0,
        "logical_scale_level": 0,
        "scale_approved": True,
        "anchor_approved": True,
        "default_object_role": "terrain",
        "palette_path": (
            "洞穴与地下城/墙体模块/赤月峡谷墙体/"
            f"直墙/{module['axis']}"
        ),
        "source_external_path": SOURCE_EXTERNAL_PATH,
        "source_provenance_path": res_path(PROVENANCE_PATH),
        "source_sha256": combined_source_sha256,
        "source_front_sha256": front_sha256,
        "source_cap_sha256": cap_sha256,
        "source_clipboard_sha256": clipboard_sha256 or "",
        "output_sha256": digest,
        "thumbnail_source_sha256": digest,
        "processing": "dominant_alpha_bbox_then_native_flat_texture_to_exact_64x32_isometric_planes",
        "generation_source_ids": [
            *[
                f"imagegen:{IMAGEGEN_SESSION_ID}/{output_id}"
                for output_id in all_front_output_ids
            ],
            f"imagegen:{IMAGEGEN_SESSION_ID}/{CAP_OUTPUT_ID}",
        ],
        "generation_source_info": {
            "tool": "image_gen.imagegen",
            "session_id": IMAGEGEN_SESSION_ID,
            "front_output_ids": all_front_output_ids,
            "front_crop_boxes": [
                list(spec["crop_box_in_raw_source"]) for spec in FRONT_SPECS
            ],
            "cap_output_id": CAP_OUTPUT_ID,
            "cap_derivation": "dominant_alpha_bbox_then_four_quadrant_windows",
        },
        "tags": [
            "cave_dungeon",
            "chiyue_valley",
            "natural_cave",
            "wet_karst",
            "rock_wall",
            "moss",
            "mineral_vein",
            FAMILY_ID,
            "straight",
            "straight_overlap",
            "manual_collision",
        ],
        "editable": True,
        "runtime_export": True,
    }
    return module, asset


def build_provenance(provenance_sources: list[dict]) -> dict:
    clipboard_available = Path(CLIPBOARD_REFERENCE_PATH).is_file()
    clipboard_sha256 = (
        sha256(Path(CLIPBOARD_REFERENCE_PATH)) if clipboard_available else None
    )
    # The task's reference is recorded even if a future rebuild happens after
    # the temporary clipboard file has gone away.
    if clipboard_sha256 is not None and clipboard_sha256 != CLIPBOARD_REFERENCE_SHA256:
        raise RuntimeError("clipboard reference SHA256 changed unexpectedly")
    return {
        "provenance_schema_version": 1,
        "family_id": FAMILY_ID,
        "socket_profile_id": SOCKET_ID,
        "generation": {
            "tool": "image_gen.imagegen",
            "session_id": IMAGEGEN_SESSION_ID,
            "front_output_id": FRONT_BASE_OUTPUT_ID,
            "front_output_ids": [FRONT_BASE_OUTPUT_ID],
            "cap_output_id": CAP_OUTPUT_ID,
            "cap_external_path": CAP_EXTERNAL_PATH,
            "front_external_path": str(_external_path(FRONT_BASE_OUTPUT_ID)),
            "front_external_paths": [str(_external_path(FRONT_BASE_OUTPUT_ID))],
            "front_crop_boxes": [
                list(spec["crop_box_in_raw_source"]) for spec in FRONT_SPECS
            ],
            "source_crop_policy": "front_internal_hard_rock_windows_and_cap_dominant_alpha_crop",
            "cap_derivation_policy": "dominant_alpha_bbox_then_four_deterministic_quadrant_windows",
            "style_contract": {
                "material": "hard_planar_wet_cave_rock",
                "palette": "wet_gray_black_rock_with_sparse_dark_red_brown_mineral_veins",
                "lighting": "wet_highlights_on_rock_planes_with_deep_fissures",
                "moss": "confined_to_fissures",
                "variation": "front_texture_window_and_cap_crop_only",
                "prohibited": "organic_folds_roots_tumors_scales_brickwork_masonry",
            },
            "clipboard_reference_path": CLIPBOARD_REFERENCE_PATH,
            "clipboard_reference_available_at_build": clipboard_available,
            "clipboard_reference_sha256": clipboard_sha256
            or CLIPBOARD_REFERENCE_SHA256,
        },
        "source_files": [
            {
                **entry,
                "sha256": entry["tracked_sha256"],
                "sha256_verified_by_builder": entry["tracked_sha256"],
            }
            for entry in provenance_sources
        ],
        "geometry_contract": {
            "tile_size": list(GRID_TILE),
            "wall_face_height_px": FACE_SIZE[1],
            "allowed_lengths": [1, 2, 3, 4],
            "slots": "iso_x/iso_y x l1/l2/l3_v01..v03/l4_v01..v03",
            "corner_join_mode": "straight_overlap",
            "corner_assets": 0,
            "collision_policy": "none",
            "collision_footprint_tiles": [0, 0],
            "collision_authority": "manual_by_user",
        },
        "art_direction": [
            "hard planar wet gray-black rock strata",
            "large fractured slabs and sharp fault lines",
            "wet highlights on high rock planes",
            "moss confined to fissures",
            "sparse dark red-brown mineral veins",
            "no organic folds, roots, tumors, scales, brickwork, masonry, gothic architecture, doors, windows, or carving",
        ],
    }


def update_family_catalog() -> None:
    catalog = read_json(FAMILY_CATALOG)
    families = [
        family
        for family in catalog.get("wall_families", [])
        if family.get("wall_family_id") != FAMILY_ID
    ]
    families.append(
        {
            "wall_family_id": FAMILY_ID,
            "display_name": "赤月峡谷天然洞穴岩壁 U0",
            "theme": "chiyue_valley",
            "material": "wet_karst_cave_rock",
            "socket_profile_id": SOCKET_ID,
            "tile_size": list(GRID_TILE),
            "wall_height_px": FACE_SIZE[1],
            "side_pad_px": 16,
            "allowed_lengths": [1, 2, 3, 4],
            "primary_lengths": [4, 3],
            "repair_lengths": [2, 1],
            "default_blocked_side": "outside",
            "seam_guard_px": 16,
            "seam_overlap_px": 0,
            "seam_cover_asset_ids": [],
            "corner_join_mode": "straight_overlap",
            "corner_asset_ids": [],
            "native_projection_contract_id": PROJECTION_CONTRACT_ID,
            "placement_contract_id": PLACEMENT_CONTRACT_ID,
            "contains_corner_pillars": False,
            "palette_id": FAMILY_ID,
            "content_layer": "personal_expansion",
            "collision_authority": "manual_by_user",
            "palette_role": "natural_chiyue_cave_rock_wall",
            "intended_uses": ["chiyue_valley_cave", "chiyue_valley_dungeon"],
            "source_provenance_path": res_path(PROVENANCE_PATH),
            "enabled": True,
        }
    )
    catalog["wall_families"] = families
    write_json(FAMILY_CATALOG, catalog)


def _clear_generated_module_dirs() -> None:
    """Remove only this pack's generated module directories, never sources."""
    if not ART_ROOT.exists():
        return
    for child in ART_ROOT.iterdir():
        if child.is_dir() and child.name.startswith(TARGET_PREFIX):
            shutil.rmtree(child)


def build_contact_sheet(assets: list[dict]) -> Path:
    columns = 4
    cell_width, cell_height = 180, 280
    sheet = Image.new(
        "RGBA",
        (columns * cell_width, ((len(assets) + columns - 1) // columns) * cell_height),
        (18, 20, 17, 255),
    )
    for index, asset in enumerate(assets):
        image_path = ROOT / str(asset["image"])
        with Image.open(image_path) as opened:
            image = opened.convert("RGBA")
        image.thumbnail((cell_width - 16, cell_height - 16), Image.Resampling.LANCZOS)
        x = (index % columns) * cell_width + (cell_width - image.width) // 2
        y = (index // columns) * cell_height + (cell_height - image.height) // 2
        sheet.alpha_composite(image, (x, y))
    PREVIEW_PATH.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(PREVIEW_PATH, format="PNG", optimize=True)
    return PREVIEW_PATH


def main() -> None:
    front_sources, cap_sources, provenance_sources = prepare_tracked_sources()
    if set(front_sources) != {1, 2, 3, 4} or set(cap_sources) != {1, 2, 3, 4}:
        raise RuntimeError("expected exactly four front and four cap source variants")

    module_catalog = read_json(MODULE_CATALOG)
    source_modules = [
        module
        for module in module_catalog.get("modules", [])
        if (
            module.get("wall_family_id") == SOURCE_FAMILY_ID
            and module.get("topology") == "straight"
        )
    ]
    if len(source_modules) != 16:
        raise RuntimeError(f"expected 16 straight source modules, found {len(source_modules)}")
    slot_counts = Counter((str(m.get("axis")), int(m.get("length_tiles", 0))) for m in source_modules)
    expected_slots = Counter(
        {
            ("iso_x", 1): 1,
            ("iso_x", 2): 1,
            ("iso_x", 3): 3,
            ("iso_x", 4): 3,
            ("iso_y", 1): 1,
            ("iso_y", 2): 1,
            ("iso_y", 3): 3,
            ("iso_y", 4): 3,
        }
    )
    if slot_counts != expected_slots:
        raise RuntimeError(f"unexpected wall slot contract: {slot_counts}")

    clipboard_sha256 = (
        sha256(Path(CLIPBOARD_REFERENCE_PATH))
        if Path(CLIPBOARD_REFERENCE_PATH).is_file()
        else CLIPBOARD_REFERENCE_SHA256
    )
    write_json(PROVENANCE_PATH, build_provenance(provenance_sources))
    _clear_generated_module_dirs()
    ART_ROOT.mkdir(parents=True, exist_ok=True)

    modules: list[dict] = []
    assets: list[dict] = []
    for source_module in source_modules:
        module, asset = build_module(
            source_module,
            front_sources,
            cap_sources,
            provenance_sources,
            clipboard_sha256,
        )
        modules.append(module)
        assets.append(asset)

    module_catalog["modules"] = [
        module
        for module in module_catalog.get("modules", [])
        if module.get("wall_family_id") != FAMILY_ID
    ] + modules
    write_json(MODULE_CATALOG, module_catalog)
    update_family_catalog()
    write_json(
        ASSET_CATALOG,
        {
            "asset_schema_version": 2,
            "catalog_id": "chiyue_valley_wall_pack",
            "display_name": "赤月峡谷天然洞穴岩壁直墙素材包",
            "source_policy": "one_hard_planar_front_base_four_internal_windows_plus_existing_cap_quadrant_crops_native_2to1_projection",
            "native_projection_contract_id": PROJECTION_CONTRACT_ID,
            "placement_contract_id": PLACEMENT_CONTRACT_ID,
            "corner_join_mode": "straight_overlap",
            "wall_family_ids": [FAMILY_ID],
            "collision_authority": "manual_by_user",
            "palette_role": "natural_chiyue_cave_rock_wall",
            "source_provenance_path": res_path(PROVENANCE_PATH),
            "preview_path": res_path(PREVIEW_PATH),
            "assets": assets,
        },
    )
    preview = build_contact_sheet(assets)
    print(
        f"CHIYUE_VALLEY_WALL_BUILD_OK modules={len(modules)} "
        f"pngs={sum(1 + len(m.get('render_parts', [])) for m in modules)} "
        f"corners=0 pillars=0 preview={preview} root={ART_ROOT}"
    )


if __name__ == "__main__":
    main()
